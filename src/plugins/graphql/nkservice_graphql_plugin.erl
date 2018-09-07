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

%% @doc NkDomain GraphQL Plugin
-module(nkservice_graphql_plugin).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([plugin_deps/0, plugin_config/3, plugin_start/4, plugin_update/5]).
-export([get_actor_types/1, get_actor_config/2,
         get_actor_queries/1, get_actor_query_meta/2,
         get_actor_connections/1, get_actor_connection_meta/2,
         get_actor_mutations/1, get_actor_mutation_meta/2]).
-export([has_graphiql/2]).

-define(LLOG(Type, Txt, Args), lager:Type("NkDOMAIN GraphQL Plugin: "++Txt, Args)).

-include_lib("nkservice/include/nkservice_actor.hrl").
-include_lib("nkpacket/include/nkpacket.hrl").


%% ===================================================================
%% Types
%% ===================================================================



%% ===================================================================
%% Plugin callbacks
%% ===================================================================



%% @doc
plugin_deps() ->
    [nkservice_rest].


plugin_config(_, #{id:=Id, config:=Config}=Spec, #{id:=SrvId}) ->
    Syntax = #{
        makeGraphqlSchema => boolean,
        graphqlActorModules => {list, binary},
        graphiqlUrl => binary,
        graphiqlUrl_opts => nkpacket_syntax:safe_syntax(),
        graphiql_debug => {list, {atom, [ws, http, nkpacket]}},
        '__allow_unknown' => true
    },
    case nklib_syntax:parse(Config, Syntax) of
        {ok, #{makeGraphqlSchema:=true}=Parsed, _} ->
            Cache1 = nkservice_config_util:get_cache_map(Spec),
            Modules = maps:get(graphqlActorModules, Parsed, []),
            Cache2 = make_type_cache(Modules, Cache1),
            Cache3 = make_queries_cache(Modules, Cache2),
            Cache4 = make_connections_cache(Modules, Cache3),
            Cache5 = make_mutations_cache(Modules, Cache4),
            Spec2 = nkservice_config_util:set_cache_map(Cache5, Spec),
            Debug1 = nkservice_config_util:get_debug_map(Spec2),
            Debug2 = lists:foldl(
                fun(Type, Acc) -> set_debug(Id, Type, Acc) end,
                Debug1,
                maps:get(graphiql_debug, Parsed, [])),
            Spec3 = nkservice_config_util:set_debug_map(Debug2, Spec2),
            case make_listen(SrvId, Id, Parsed) of
                {ok, _Listeners} ->
                    {ok, Spec3#{config := Parsed}};
                {error, Error} ->
                    {error, Error}
            end;
        {ok, _Parsed, _} ->
            {ok, Spec};
        {error, Error} ->
            {error, Error}
    end;

plugin_config(_Class, _Package, _Service) ->
    continue.


%% @doc
plugin_start(_, #{id:=Id, config:=Config}, Pid, #{id:=SrvId}) ->
    case Config of
        #{makeGraphqlSchema:=true} ->
            ?LLOG(notice, "loading GraphQL schema", []),
            nkservice_graphql:load_schema(SrvId);
        _ ->
            ok
    end,
    {ok, Listeners} =  make_listen(SrvId, Id, Config),
    insert_listeners(Id, Pid, Listeners);

plugin_start(_Id, _Spec, _Pid, _Service) ->
    continue.


%% @doc
%% Even if we are called only with modified config, we check if the spec is new
plugin_update(_, #{id:=Id, config:=NewConfig}, OldSpec, Pid, #{id:=SrvId}) ->
    case OldSpec of
        #{config:=NewConfig} ->
            ok;
        _ ->
            {ok, Listeners} =  make_listen(SrvId, Id, NewConfig),
            insert_listeners(Id, Pid, Listeners)
    end;

plugin_update(_Class, _NewSpec, _OldSpec, _Pid, _Service) ->
    ok.


%% ===================================================================
%% Cache
%% ===================================================================

-type cache_key() ::
    types |
    {type, Type::binary()} |       % Get config
    queries |
    {query_meta, Name::binary()} |
    connections |
    {connection_meta, Name::binary()} |
    mutations |
    {mutation_meta, Name::binary()}.


%% @doc
-spec get_domain_cache(nkservice:id(), cache_key()) ->
    term().

get_domain_cache(SrvId, CacheKey) ->
    nkservice_util:get_cache(SrvId, nkservice_graphql, single, CacheKey).


%% @doc
get_actor_types(SrvId) ->
    get_domain_cache(SrvId, types).


%% @doc
get_actor_config(SrvId, Type) when is_binary(Type) ->
    get_domain_cache(SrvId, {type_config, Type}).


%% @doc Get all queries
get_actor_queries(SrvId) ->
    get_domain_cache(SrvId, queries).


%% @doc Get query params
get_actor_query_meta(SrvId, Name) when is_binary(Name) ->
    get_domain_cache(SrvId, {query_meta, Name}).


%% @doc Get all connections
get_actor_connections(SrvId) ->
    get_domain_cache(SrvId, connections).


%% @doc Get connection params
get_actor_connection_meta(SrvId, Name) when is_binary(Name) ->
    get_domain_cache(SrvId, {connection_meta, Name}).


%% @doc Get all mutations
get_actor_mutations(SrvId) ->
    get_domain_cache(SrvId, mutation).


%% @doc Get mutation params
get_actor_mutation_meta(SrvId, Name) when is_binary(Name) ->
    get_domain_cache(SrvId, {mutation_meta, Name}).


%% @private
has_graphiql(SrvId, PackageId) ->
    Config = nkservice_util:get_config(SrvId, PackageId),
    maps:is_key(graphiqlUrl, Config).



%% ===================================================================
%% Internal
%% ===================================================================



%% @private
get_cache(Key, Cache, Default) ->
    nkservice_config_util:get_cache_key(nkservice_graphql, single, Key, Cache, Default).

%% @private
set_cache(Key, Val, Cache) ->
    nkservice_config_util:set_cache_key(nkservice_graphql, single, Key, Val, Cache).

%% @private
set_debug(Id, Type, Debug) ->
    nkservice_config_util:set_debug_key(nkservice_graphql, Id, Type, true, Debug).


%% @private
make_type_cache([], Cache) ->
    Cache;

make_type_cache([Module|Rest], Cache) ->
    Module2 = nklib_util:to_atom(Module),
    code:ensure_loaded(Module2),
    Config = case Module2:config() of
        not_exported ->
            ?LLOG(error, "Invalid graphQL actor callback module '~s'", [Module2]),
            error({module_unknown, Module2});
        Config0 ->
            Config0
    end,
    Type = to_bin(maps:get(type, Config)),
    Config2 = #{
        module => Module2,
        type => Type,
        actor_class => nklib_util:to_binary(maps:get(actor_class, Config)),
        actor_type => nklib_util:to_binary(maps:get(actor_type, Config))
    },
    Types1 = get_cache(types, Cache, []),
    Types2 = lists:usort([Type|Types1]),
    Cache2 = set_cache(types, Types2, Cache),
    Cache3 = set_cache({type_config, Type}, Config2, Cache2),
    make_type_cache(Rest, Cache3).


%% @private
make_queries_cache([], Cache) ->
    Cache;

make_queries_cache([Module|Rest], Cache) ->
    Module2 = nklib_util:to_atom(Module),
    Cache2 = maps:fold(
        fun
            (Name, {_Result, Opts}, Acc) ->
                Name2 = to_bin(Name),
                Queries1 = get_cache(queries, Acc, []),
                Queries2 = lists:usort([Name2|Queries1]),
                Acc2 = set_cache(queries, Queries2, Acc),
                Meta1 = maps:get(meta, Opts, #{}),
                Meta2 = Meta1#{module => Module2},
                set_cache({query_meta, Name2}, Meta2, Acc2);
            (_Name, _, Acc) ->
                Acc
        end,
        Cache,
        Module2:schema(queries)
    ),
    make_queries_cache(Rest, Cache2).


%% @private
make_connections_cache([], Cache) ->
    Cache;

make_connections_cache([Module|Rest], Cache) ->
    Module2 = nklib_util:to_atom(Module),
    Cache2 = case erlang:function_exported(Module2, connections, 1) of
        true ->
            Types = get_cache(types, Cache, []),
            lists:foldl(
                fun(Type, Acc1) ->
                    maps:fold(
                        fun
                            (Name, {_Result, Opts}, Acc2) ->
                                Name2 = to_bin(Name),
                                Connection1 = get_cache(connections, Acc2, []),
                                Connection2 = lists:usort([Name2|Connection1]),
                                Acc3 = set_cache(connections, Connection2, Acc2),
                                Meta1 = maps:get(meta, Opts, #{}),
                                Meta2 = Meta1#{module => Module2},
                                set_cache({connection_meta, Name2}, Meta2, Acc3);
                            (_Name, _, Acc2) ->
                                Acc2
                        end,
                        Acc1,
                        Module2:connections(Type))
                end,
                Cache,
                Types
            );
        false ->
            Cache
    end,
    make_connections_cache(Rest, Cache2).


%% @private
make_mutations_cache([], Cache) ->
    Cache;

make_mutations_cache([Module|Rest], Cache) ->
    Module2 = nklib_util:to_atom(Module),
    Cache2 = maps:fold(
        fun
            (Name, {_Result, Opts}, Acc) ->
                Name2 = to_bin(Name),
                Queries1 = get_cache(mutations, Acc, []),
                Queries2 = lists:usort([Name2|Queries1]),
                Acc2 = set_cache(mutations, Queries2, Acc),
                Meta1 = maps:get(meta, Opts, #{}),
                Meta2 = Meta1#{module => Module2},
                set_cache({mutation_meta, Name2}, Meta2, Acc2);
            (_Name, _, Acc) ->
                Acc
        end,
        Cache,
        Module2:schema(mutations)
    ),
    make_mutations_cache(Rest, Cache2).



%% @private
make_listen(SrvId, _Id, #{graphiqlUrl:=Url}=Entry) ->
    ResolveOpts = #{resolve_type=>listen, protocol=>nkservice_rest_protocol},
    case nkpacket_resolve:resolve(Url, ResolveOpts) of
        {ok, Conns} ->
            Opts1 = maps:get(graphiqlUrl_opts, Entry, #{}),
            Debug = maps:get(graphiql_debug, Entry, []),
            Opts2 = Opts1#{debug=>lists:member(nkpacket, Debug)},
            make_listen_transps(SrvId, <<"nkservice-graphiql">>, Conns, Opts2, []);
        {error, Error} ->
            {error, Error}
    end;

make_listen(_SrvId, _Id, _Entry) ->
    {ok, []}.



%% @private
make_listen_transps(_SrvId, _Id, [], _Opts, Acc) ->
    {ok, Acc};

make_listen_transps(SrvId, Id, [Conn|Rest], Opts, Acc) ->
    #nkconn{opts=ConnOpts} = Conn,
    Opts2 = maps:merge(ConnOpts, Opts),
    Opts3 = Opts2#{
        id => Id,
        class => {nkservice_rest, SrvId, Id},
        path => maps:get(path, Opts2, <<"/">>),
        get_headers => [<<"user-agent">>]
    },
    Conn2 = Conn#nkconn{opts=Opts3},
    case nkpacket:get_listener(Conn2) of
        {ok, Id, Spec} ->
            make_listen_transps(SrvId, Id, Rest, Opts, [Spec|Acc]);
        {error, Error} ->
            {error, Error}
    end.


%% @private
insert_listeners(Id, Pid, SpecList) ->
    case nkservice_packages_sup:update_child_multi(Pid, SpecList, #{}) of
        ok ->
            ?LLOG(debug, "started ~s", [Id]),
            ok;
        not_updated ->
            ?LLOG(debug, "didn't upgrade ~s", [Id]),
            ok;
        upgraded ->
            ?LLOG(info, "upgraded ~s", [Id]),
            ok;
        {error, Error} ->
            ?LLOG(notice, "start/update error ~s: ~p", [Id, Error]),
            {error, Error}
    end.


%% @private
to_bin(T) when is_binary(T)-> T;
to_bin(T) -> nklib_util:to_binary(T).



