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

%% NOTE: NkSIP project is a great tester for NkSERVICE
%%

-module(basic_test).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-compile([export_all]).
-include_lib("nklib/include/nklib.hrl").
-include_lib("eunit/include/eunit.hrl").

basic_test_() ->
  	{setup, 
    	fun() -> 
    		ok = nkservice_app:start()
		end,
		fun(_) -> 
			ok 
		end,
	    fun(_) ->
		    [
				fun() -> basic() end
			]
		end
  	}.




basic() ->
	Name = "serv1@root",
	nkservice:stop(Name),
	timer:sleep(100),
	SrvSpec = #{
		class => class1,
		log_level=> info,
		data1 => value1,
		plugins => serv1
	},
	SrvId = aqcaxj1,
	{ok, SrvId} = nkservice:start(Name, SrvSpec),
	{error, already_started} = nkservice:start(Name, SrvSpec),
	[{SrvId, "serv1@root", class1, SrvPid}] = nkservice:get_all(),
	[{SrvId, "serv1@root", SrvPid}] = nkservice:get_all(class1),

	[plug2, plug1, plug3, serv1] = SrvId:plugins(),

	7 = SrvId:log_level(),
	#{
		class := class1,
  		data1 := value1,
  		id := aqcaxj1,
  		log_level := 7,
  		name := "serv1@root",
  		plug1 := ok,
  		plug2 := ok,
  		plug3 := ok,
  		plugins := [plug2,plug1,plug3,serv1],
  		serv1 := ok
  	} = 
  		nkservice:get_spec(Name),

	{fun11_serv1, a} = SrvId:fun11(a),
	{fun12_plug1, {serv1, a}, b} = SrvId:fun12(a,b),
	{fun13_plug1, a, b, c} = SrvId:fun13(a,b,c),
	{fun21_serv1, a} = SrvId:fun21(a),
	{fun22_plug2, {plug1, {serv1, a}}, b} = SrvId:fun22(a,b),
	{fun23_plug2, a, b, c} = SrvId:fun23(a,b,c),
	{fun31_serv1, a} = SrvId:fun31(a),
	{fun32_plug3, {serv1, a}, b} = SrvId:fun32(a, b),
	{fun33_plug3, c} = SrvId:fun33(c),

	ok = nkservice:update(SrvId, #{data1=>value2}),
	#{class:=class1, data1:=value2} = nkservice:get_spec(SrvId),

	ok = meck:expect(serv1, plugin_deps, fun() -> [plug1] end),
	ok = nkservice:update(SrvId, #{data1=>value3, plugins=>[serv1]}),
	[plug2, plug1, serv1] = SrvId:plugins(),
	#{plug1:=ok, plug2:=ok, serv1:=ok, data1:=value3} = Spec3 = nkservice:get_spec(SrvId),
	false = maps:is_key(plug3, Spec3),

	ok = meck:expect(plug1, plugin_deps, fun() -> [] end),
	ok = nkservice:update(SrvId, #{data1=>value4, plugins=>[serv1]}),
	[plug1, serv1] = SrvId:plugins(),
	#{plug1:=ok, serv1:=ok, data1:=value4} = Spec4 = nkservice:get_spec(SrvId),
	false = maps:is_key(plug2, Spec4),
	false = maps:is_key(plug3, Spec4),

	meck:unload(serv1),
	meck:unload(plug1),
	code:load_file(serv1),
	code:load_file(plug1),
	nkservice:stop(SrvId),
	ok.






