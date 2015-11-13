%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Carlos Gonzalez Florido.  All Rights Reserved.
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

-module(basic_test).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-compile([export_all]).
-include_lib("nklib/include/nklib.hrl").
-include_lib("eunit/include/eunit.hrl").

% basic_test_() ->
%   	{setup, 
%     	fun() -> 
%     		ok = nkdomain_app:start()
% 		end,
% 		fun(_) -> 
% 			ok 
% 		end,
% 	    fun(_) ->
% 		    [
% 				fun() -> load() end,
%                 fun() -> data() end,
%                 fun() -> update() end
% 			]
% 		end
%   	}.




basic() ->
	SrvId = 'serv1@root',
	nkservice:stop(SrvId),
	timer:sleep(100),
	SrvSpec = #{
		class => class1,
		config => #{log_level=>info, cache1=>value1},
		data1 => value1
	},
	{ok, _Pid} = nkservice_server:start_link(SrvId, serv1, SrvSpec),

	Plugins = SrvId:plugins(),
	true = 
		Plugins == [plug2, plug1, plug3, serv1] orelse
		Plugins == [plug3, plug2, plug1, serv1],

	info = SrvId:config_log_level(),
	value1 = SrvId:config_cache1(),
	#{data1:=value1} = nkservice_server:get_cache(SrvId, spec),
	#{plug1:=ok, plug2:=ok, plug3:=ok, serv1:=ok} =
		 nkservice_server:get_cache(SrvId, env),

	{fun11_serv1, a} = SrvId:fun11(a),
	{fun12_plug1, {serv1, a}, b} = SrvId:fun12(a,b),
	{fun13_plug1, a, b, c} = SrvId:fun13(a,b,c),
	{fun21_serv1, a} = SrvId:fun21(a),
	{fun22_plug2, {plug1, {serv1, a}}, b} = SrvId:fun22(a,b),
	{fun23_plug2, a, b, c} = SrvId:fun23(a,b,c),
	{fun31_serv1, a} = SrvId:fun31(a),
	{fun32_plug3, {serv1, a}, b} = SrvId:fun32(a, b),
	{fun33_plug3, c} = SrvId:fun33(c),

	{ok, {state, any}} = SrvId:nks_service_init(any, spec),
	lager:error("Next error about an unexpected call is expected"),
	{noreply, {ok, st1}} = SrvId:nks_handle_call(any, any, st1),

	ok = nkservice:update((SrvId, #{data1=>value2}),
	#{class:=class1, data1:=value2} = nkservice_server:get_cache(SrvId, spec),

	ok = meck:expect(serv1, deps, fun() -> [{plug1, ".*"}] end),
	ok = nkservice:update((SrvId, #{data1=>value3}),
	#{plug1:=ok, plug2:=ok, serv1:=ok} = nkservice_server:get_cache(SrvId, env),
	ok = meck:expect(plug1, deps, fun() -> [] end),
	ok = nkservice:update((SrvId, #{data1=>value4}),
	#{plug1:=ok, serv1:=ok} = nkservice_server:get_cache(SrvId, env),

	meck:unload(serv1),
	meck:unload(plug1),
	code:load_file(serv1),
	code:load_file(plug1),
	nkservice:stop(SrvId),
	ok.






