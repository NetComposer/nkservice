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
-export([get_filter_field_type/2, get_sort_field/2]).

-define(LLOG(Type, Txt, Args), lager:Type("NkDOMAIN GraphQL Plugin: "++Txt, Args)).

%%-include("nkdomain.hrl").
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


%% @doc
%% We store in cache
%% - {nkservice_graphql, any, filter_fields}
%% - {nkservice_graphql, any, sort_fields}


plugin_config(_, #{id:=Id, config:=Config}=Spec, #{id:=SrvId}) ->
    Syntax = #{
        makeGraphqlSchema => boolean,
        graphiqlUrl => binary,
        graphiqlUrl_opts => nkpacket_syntax:safe_syntax(),
        graphiql_debug => {list, {atom, [ws, http, nkpacket]}},
        '__allow_unknown' => true
    },
    case nklib_syntax:parse(Config, Syntax) of
        {ok, Parsed, _} ->
            CacheMap1 = nkservice_config_util:get_cache_map(Spec),
            FilterFields1 = get_cache(filter_fields, CacheMap1),
            FilterFields2 = nkservice_graphql_schema:core_filter_fields(),
            FilterFields3 = maps:merge(FilterFields1, FilterFields2),
            CacheMap2 = set_cache(filter_fields, FilterFields3, CacheMap1),
            SortFields1 = get_cache(sort_fields, CacheMap1),
            SortFields2 = nkservice_graphql_schema:core_sort_fields(),
            SortFields3 = maps:merge(SortFields1, SortFields2),
            CacheMap3 = set_cache(sort_fields, SortFields3, CacheMap2),
            Spec2 = nkservice_config_util:set_cache_map(CacheMap3, Spec),
            DebugMap1 = nkservice_config_util:get_debug_map(Spec2),
            DebugMap2 = lists:foldl(
                fun(Type, Acc) -> set_debug(Id, Type, Acc) end,
                DebugMap1,
                maps:get(graphiql_debug, Parsed, [])),
            Spec3 = nkservice_config_util:set_debug_map(DebugMap2, Spec2),
            case make_listen(SrvId, Id, Parsed) of
                {ok, _Listeners} ->
                    {ok, Spec3#{config := Parsed}};
                {error, Error} ->
                    {error, Error}
            end;
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
plugin_update(_, #{id:=Id, config:=#{graphiqlUrl:=_}=NewConfig}, OldSpec, Pid, #{id:=SrvId}) ->
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


%% @doc
get_filter_field_type(SrvId, Field) ->
    Field2 = to_bin(Field),
    Fields = nkservice_util:get_cache(SrvId, nkservice_graphql, any, filter_fields),
    case maps:get(Field2, Fields) of
        {Type, Field3} ->
            {Field3, Type};
        Type ->
            {Field2, Type}
    end.


%% @doc
get_sort_field(SrvId, Field) ->
    Field2 = to_bin(Field),
    Fields = nkservice_util:get_cache(SrvId, nkservice_graphql, any, sort_fields),
    case maps:get(Field2, Fields) of
        {Type, Field3} ->
            {Field3, Type};
        Type ->
            {Field2, Type}
    end.


%% ===================================================================
%% Internal
%% ===================================================================

%% @private
get_cache(Key, Map) ->
    nkservice_config_util:get_cache_key(nkservice_graphql, any, Key, Map, #{}).

%% @private
set_cache(Key, Val, Map) ->
    nkservice_config_util:set_cache_key(nkservice_graphql, any, Key, Val, Map).

%% @private
set_debug(Id, Type, Map) ->
    nkservice_config_util:set_debug_key(nkservice_graphql, Id, Type, true, Map).


%% @private
make_listen(SrvId, _Id, #{graphiqlUrl:=Url}=Entry) ->
    ResolveOpts = #{resolve_type=>listen, protocol=>nkservice_rest_protocol},
    case nkpacket_resolve:resolve(Url, ResolveOpts) of
        {ok, Conns} ->
            Opts1 = maps:get(graphiqlUrl_opts, Entry, #{}),
            Debug = maps:get(graphiql_debug, Entry, []),
            Opts2 = Opts1#{debug=>lists:member(nkpacket, Debug)},
            make_listen_transps(SrvId, <<"domains-graphiql">>, Conns, Opts2, []);
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



