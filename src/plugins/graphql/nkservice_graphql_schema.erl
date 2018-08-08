%% -------------------------------------------------------------------
%%
%% Copyright (c) 2018 Carlos Gonzalez Florido.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc NkDomain main module
-module(nkservice_graphql_schema).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([actor_query/3]).
-export([make_schema/1]).
-export_type([schema_class/0, schema_type/0]).


%% ===================================================================
%% Types
%% ===================================================================

-type config() ::
    #{
        type => atom(),
        actor_class => nkservice_actor:class(),
        actor_type => nkservice_actor:type()
    }.


-type schema_class() ::
    scalars|enums|types|inputs|interfaces|queries|mutations.

-type schema_type() ::
    id | integer | boolean | string | object | time | atom().

-type name() :: atom().

-type field_value() ::
    schema_type() | {schema_type(), field_opts()} |
    {no_null, schema_type()} | {no_null, schema_type(), field_opts()} |
    {list, schema_type()} | {list, schema_type(), field_opts()} |
    {list_not_null, schema_type()} | {list_not_null, schema_type(), field_opts()} |
    {connection, schema_type()} | {connection, schema_type(), field_opts()}.

-type field_opts() ::
    #{
        params => #{name() => field_value()},
        default => string(),
        comment => string(),
        meta => map()
    }.

-type schema_fields() ::
    #{name() => field_value()}.


%% @doc Schema definitions when calling schema/2
-type schema_def() ::

    % Scalars
    #{name() => #{comment => string()}} |

    % Enums
    #{name() => #{opts => [atom()], comment => string()}} |

    % Types
    % For 'actor' class
    % - implements Node and Actor
    % - default fields (schema_actor_fields/1) are added
    % - schema is searched for connections for this Type (see connections/2)
    % - a type 'ActorSearchResult' is added
    % - inputs 'ActorQueryFilter', 'ActorFilterFields' and 'ActorQuerySort' are added
    % For 'connection' class
    % - fields actors => {list, Actor} and totalCount are added
    #{
        name() => #{
            class => none | actor | connection,
            fields => schema_fields(),
            comment => string(),
            filter_fields => schema_fields(),
            sort_fields => schema_fields()
        }
    } |

    % Inputs:
    #{
        name() => #{
            fields => schema_fields(),
            comment => string()
        }
    } |

    % Interfaces
    #{
        name() => #{
            fields => schema_fields(),
            comment => string()
        }
    } |

    % Queries
    % 'meta' is merged to query params
    #{name() => field_value()} |

    % Mutations
    #{
        name() => #{
            inputs => schema_fields(),
            outputs => schema_fields(),
            comment => string()
        }
    }.


%% ===================================================================
%% Behavior callbacks definitions
%% ===================================================================


-callback config() ->
    config().

-callback schema(nkservice:id()) ->
    schema_def().

-callback connections(name()) ->
    #{name() => field_value()}.



%% ===================================================================
%% Public
%% ===================================================================


%% @doc
% Uses ActorSearchResult, ActorQueryFilter, ActorQuerySort
% ActorSearchResult is created automatically by type if class = actor
% (nkservice_graphql_schema_lib)
% ActorQueryFilter and ActorQuerySort
actor_query(BaseType, Params, Meta) ->
    Result = nklib_util:to_atom(<<(to_bin(BaseType))/binary, "SearchResult">>),
    Filter = nklib_util:to_atom(<<(to_bin(BaseType))/binary, "FilterSpec">>),
    Sort = nklib_util:to_atom(<<(to_bin(BaseType))/binary, "SortFields">>),
    {Result, #{
        params => Params#{
            filter => Filter,
            sort => {list, Sort}
        },
        meta => Meta
    }}.


%% ===================================================================
%% Private
%% ===================================================================


%% @doc Generates and schema
make_schema(SrvId) ->
    nkservice_graphql_schema_lib:make_schema(SrvId).


%% @private
to_bin(Term) when is_binary(Term) -> Term;
to_bin(Term) -> nklib_util:to_binary(Term).