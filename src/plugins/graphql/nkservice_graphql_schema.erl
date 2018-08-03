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

-export([make_schema/1]).
-export([core_filter_fields/0, core_sort_fields/0]).
-export_type([schema_class/0, schema_type/0]).


%% ===================================================================
%% Types
%% ===================================================================

-type schema_class() ::
    scalars|enums|types|inputs|interfaces|queries|mutations.

-type schema_type() ::
    id | int | boolean | string | object | time | atom().

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
        comment => string()
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
    % - a type 'ActorSeachResult' is added
    % For 'connection' class
    % - fields actors => {list, Actor} and totalCount are added
    #{
        name() => #{
            class => none | actor | connection,
            fields => schema_fields(),
            comment => string()
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


-callback actor_type() ->
    name().

-callback schema(nkservice:id()) ->
    schema_def().

-callback connections(name()) ->
    #{name() => field_value()}.


%% ===================================================================
%% Private
%% ===================================================================


%% @doc Generates and schema
make_schema(SrvId) ->
    nkservice_graphql_schema_lib:make_schema(SrvId).



%% @doc Used by queries
core_filter_fields() ->
    #{
        <<"type">> => {string, <<"kind">>},
        <<"name">> => string,
        <<"id">> => {string, <<"uid">>},
        <<"domain">> => {string, <<"srv">>},
        <<"metadata.createdTime">> => integer,
        <<"metadata.description">> => string,
        <<"metadata.isEnabled">> => boolean,
        <<"metadata.expiresTime">> => integer
    }.


%% @doc Used by queries
core_sort_fields() ->
    #{
        <<"type">> => {string, <<"kind">>},
        <<"name">> => string,
        <<"domain">> => {string, <<"srv">>},
        <<"metadata">> => string,
        <<"metadata.createdTime">> => integer,
        <<"metadata.expiresTime">> => integer,
        <<"metadata.isEnabled">> => boolean
    }.

