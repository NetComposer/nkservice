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

-export([actor_query/2]).
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


%% Called when creating schema, for a type with class=actor
%% (nkservice_graphql_schema_lib)
-callback connections(name()) ->
    #{name() => field_value()}.


%% @doc Called when a query, connection or mutation are defined in the callback module
-callback query(nkservice:id(), Name::binary(), Params::map(), Meta::map(), Ctx::map()) ->
    {ok, nkservice_graphql:object()} | {error, term()} |  continue.


-callback mutation(nkservice:id(), Name::binary(), Params::map(), Meta::map(), Ctx::map()) ->
    {ok, nkservice_graphql:object()} | {error, term()} |  continue.


-callback execute(nkservice:id(), Field::binary(), nkservice_graphql:object(), Meta::map(), Args::map()) ->
    {ok, nkservice_graphql:object()} | {error, term()} |  continue.


-optional_callbacks([connections/1, query/5, mutation/5, execute/5]).


%% ===================================================================
%% Public
%% ===================================================================


%% @doc
% Refers to ActorSearchResult, ActorQueryFilter, ActorQuerySort
% They are created automatically by type if class = actor
% (nkservice_graphql_schema_lib)
actor_query(BaseType, Opts) ->
    Result = <<(to_bin(BaseType))/binary, "SearchResult">>,
    Filter = <<(to_bin(BaseType))/binary, "FilterSpec">>,
    Sort = <<(to_bin(BaseType))/binary, "SortFields">>,
    Params = maps:get(params, Opts, #{}),
    {Result, Opts#{
        params => Params#{
            filter => Filter,
            sort => {list, Sort}
        }
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