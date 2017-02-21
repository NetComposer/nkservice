%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Carlos Gonzalez Florido.  All Rights Reserved.
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

%% @doc Backend module for luerl supporting ETS KV operations
-module(nkservice_luerl_kv).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([install/1, erl_get/2]).

%% @private Get values stored by LUA in raw format
%% - For string, we get a binary
%% - For numbers, we get a float
%% - For true/false/nil we get an atom
%% - For tables, we get a #tref{}
%%   we can call luerl:decode/2 to get the real table (but need the state)
%% - For functions, we get #function{} with the full function AST
%%   we can call it with luerl:call(#function{}, Args [,State])
%% - If the key is not defined, we get 'undefined'
%%
erl_get(Serv, Key) ->
    case nkservice_srv:get_srv_id(Serv) of
        {ok, SrvId} ->
            Val = nkservice:get(SrvId, {luerl, Key}),
            {ok, Val};
        not_found ->
            {error, service_not_found}
    end.


%% @private
install(St) ->
    luerl_emul:alloc_table(table(), St).


%% @private
table() ->
    [
        {<<"get">>, {function, fun get/2}},
        {<<"put">>, {function, fun put/2}},
        {<<"put_new">>, {function, fun put_new/2}},
        {<<"del">>, {function, fun del/2}}
    ].



%% @private
get([Key], LuerlState) ->
    get([Key, <<"undefined">>], LuerlState);

get([Key, Default], LuerlState) ->
    SrvId = get(srv_id),
    Res1 = nkservice:get(SrvId, {luerl, Key}, Default),
    {[Res1], LuerlState}.


%% @private
put([Key, Value], LuerlState) when is_binary(Key) ->
    SrvId = get(srv_id),
    nkservice:put(SrvId, {luerl, Key}, Value),
    {[true], LuerlState}.


%% @private
put_new([Key, Value], LuerlState) when is_binary(Key) ->
    SrvId = get(srv_id),
    Res = nkservice:put_new(SrvId, {luerl, Key}, Value),
    {[Res], LuerlState}.


%% @private
del([Key], LuerlState) when is_binary(Key) ->
    SrvId = get(srv_id),
    nkservice:del(SrvId, {luerl, Key}),
    {[true], LuerlState}.


% To test:
%
% function kv_test1()
%     assert(kv.del("key1"))
%     assert(kv.del("key2"))
%     assert(kv.get("key1") == "undefined")
%     assert(kv.get("key1", "default") == "default")
%     assert(kv.get(1) == "undefined")
%     assert(kv.put("key1", "value1"))
%     assert(kv.get("key1") == "value1")
%     assert(kv.put_new("key1", "value2") == false)
%     assert(kv.put_new("key2", "value2"))
%     assert(kv.put("key1", "value1"))
%     assert(kv.put("key2", "value2"))
% end
%
%
% function kv_test2()
%     kv.del("key3")
%     kv.put("key3", 1)
%     assert(kv.get("key3") == 1)
%     kv.put("key3", true)
%     assert(kv.get("key3") == true)
%     kv.put("key3", {a=1})
%     t = kv.get("key3")
%     assert(type(t)=="table")
%     assert(t.a==1)
%     kv.put("key3", kv_test3)
%     f = kv.get("key3")
%     assert(type(f)=="function")
%     assert(f(1)==2)
% end
%
%
% function kv_test3(a)
%     return a+1
% end
%
% function kv_test4()
%     kv.put("v1", 1)
%     kv.put("v2", "v2")
%     kv.put("v3", true)
%     kv.put("v4", nil)
%     kv.put("v5", {a=1})
%     kv.put("v6", kv_test3)
% end


