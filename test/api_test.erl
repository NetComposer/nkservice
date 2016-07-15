-module(api_test).
-compile([export_all]).


-include_lib("nkservice.hrl").


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts the service
start() ->
	Spec = #{
		callback => ?MODULE,
        log_level => debug,
        api_server => "wss:all:9010",
        api_server_timeout => 300
	},
	nkservice:start(test, Spec).


%% @doc Stops the service
stop() -> 
	nkservice:stop(test).


%% @doc Gets all registered users and sessions
get_users() ->
	nkservice_api_server:get_all().


%% @doc Gets all sessions for a registered user
get_sessions(User) ->
	nkservice_api_server:find_user(User).


api_start(User) ->
    Fun = fun ?MODULE:api_client_fun/2,
    % Url = "nkapic://media2.netcomposer.io:9010",
    Url = "nkapic://localhost:9010",
    {ok, _, C} = nkservice_api_client:start(test, Url, User, "p1", Fun, #{}),
    C.
 

api_client_fun(#api_req{class = <<"core">>, cmd = <<"event">>, data = Data}, UserData) ->
    Class = maps:get(<<"class">>, Data),
    Sub = maps:get(<<"subclass">>, Data, <<"*">>),
    Type = maps:get(<<"type">>, Data, <<"*">>),
    ObjId = maps:get(<<"obj_id">>, Data, <<"*">>),
    Body = maps:get(<<"body">>, Data, #{}),
    lager:notice("WsClient2 event ~s:~s:~s:~s: ~p", [Class, Sub, Type, ObjId, Body]),
    {ok, #{}, UserData};

api_client_fun(#api_req{class = <<"class1">>, data=Data}=Req, UserData) ->
    lager:notice("API REQ: ~p", [lager:pr(Req, ?MODULE)]),
    {ok, Data, UserData};

api_client_fun(_Req, UserData) ->
    {error, not_implemented, UserData}.

% test1() ->
%     C1 = api_start("u1"),
%     {ok, M1} = get_user(C1, "u1"),
%     [{S1, #{}}] = maps:to_list(C1),

%     C2 = api_start("u1"),
%     {ok, M2} = get_user(C1, "u1"),
%     [{S1, #{}}] = maps:to_list(C1),
    



%     C3 = api_start("u2"),
%     {ok, Map1} = list_users(C1),
%     [{<<"u1">>, [S1A, S1B]}, {<<"u2">>, [S2]}] = lists:sort(maps:to_list(Map1)),
%     {ok, Map2} = get_user(C1, "u1"),
%     [{S1A, #{}}, {S1B, #{}}] = lists:sort(maps:to_list(Map2)),
%     {ok, List3} = get_subs(C1),
%     [
%         #{
%             <<"class">> => <<"core">>,
%             <<"obj_id">> => <<"136c8cc7-3780-9292-1c17-28f07603cda8">>,
%                                   <<"service">> => <<"aa38ayw">>,
%                                   <<"subclass">> => <<"session_event">>,
%                                   <<"type">> => <<"*">>},
%                                 #{<<"class">> => <<"core">>,
%                                   <<"obj_id">> => <<"u1">>,
%                                   <<"service">> => <<"aa38ayw">>,
%                                   <<"subclass">> => <<"user_event">>,
%                                   <<"type">> => <<"*">>}])


%     lists:sort(maps:to_list(Map3)).






list_users(C) ->
    nkservice_api_client:cmd(C, core, user, list, #{}).


get_user(C, User) ->
    nkservice_api_client:cmd(C, core, user, get, #{user => User}).


logout(C, SessId) ->
    nkservice_api_client:cmd(C, core, session, stop, #{session_id => SessId}).


get_subs(C) ->
    nkservice_api_client:cmd(C, core, event, get_subscriptions, #{}).


send_user_event(C, User) ->
    nkservice_api_client:cmd(C, 
        core, user, send_event, #{user=>User, type=>type1, body=>#{k=>v}}).    

send_session_event(C, SessId) ->
    nkservice_api_client:cmd(C, 
        core, session, send_event,#{session_id=>SessId, type=>type1, body=>#{k=>v}}).    
    
call_session(C, SessId) ->
    {ok, #{<<"k">> := <<"v">>}} = 
        nkservice_api_client:cmd(C,
            core, session, cmd, 
            #{session_id=>SessId, class=>class1, cmd=>cmd1, data=>#{k=>v}}),
    {error, {1000, <<"Not implemented">>}} = 
        nkservice_api_client:cmd(C, 
            core, session, cmd, 
            #{session_id=>SessId, class=>class2, cmd=>cmd1, data=>#{k=>v}}),
    ok.

subscribe(C) ->
    nkservice_api_client:cmd(C,
        core, event, subscribe, #{class=>class1, body=>#{k=>v}}),
    nkservice_api_client:cmd(C,
        core, event, subscribe, #{class=>class2, subclass=>s2}),
    nkservice_api_client:cmd(C,
        core, event, subscribe, #{class=>class3, subclass=>s3, type=>t3}),
    nkservice_api_client:cmd(C,
        core, event, subscribe, #{class=>class4, subclass=>s4, type=>t4, obj_id=>o4}).


send1(C, T) ->
    Ev = case T of
        s1 -> #{class=>class1, subclass=>s1, type=>t1, obj_id=>o1, body=>#{k1=>v1}};
        s2a -> #{class=>class2, subclass=>s2, type=>t2, obj_id=>o2, body=>#{k2=>v2}};
        s2b -> #{class=>class2, subclass=>s3, type=>t2, obj_id=>o2, body=>#{k2=>v2}};
        s3a -> #{class=>class3, subclass=>s3, type=>t3, obj_id=>o3, body=>#{k3=>v3}};
        s3b -> #{class=>class3, subclass=>s3, type=>t4, body=>#{k3=>v3}};
        s4a -> #{class=>class4, subclass=>s4, type=>t4, obj_id=>o4, body=>#{k4=>v4}};
        s4b -> #{class=>class4, subclass=>s4, type=>t4, obj_id=>o5, body=>#{k4=>v4}}
    end,
    nkservice_api_client:cmd(C, core, event, send, Ev).




api_1(C) ->
    nkservice_api_client:cmd(C, media, start_session, #{type=>park}).

api_2(C) ->
    Data = #{
        class => test,
        % subclass => <<"a22">>,
        body => #{a => 1}
    },
    nkservice_api_client:cmd(C, core, subscribe, Data).

api_3(C, S) ->
    nkservice_api_client:cmd(C, media, stop_session, #{session_id=>S}).


api_4(C) ->
    Data = #{
        class => test,
        subclass => <<"a23">>,
        body => #{b => 2}
    },
    nkservice_api_client:cmd(C, core, send_event, Data).




%% ===================================================================
%% API callbacks
%% ===================================================================

%% @doc
api_allow(_Req, State) ->
    % lager:notice("Api allow ~p", [_Req]),
    {true, State}.


%% @oc
api_subscribe_allow(SrvId, _Class, _SubClass, _Type, #{srv_id:=SrvId}=State) ->
    lager:notice("Subscribe allow ~s:~s:~s", [_Class, _SubClass, _Type]),
    {true, State};

api_subscribe_allow(_Class, _SubClass, _Type, _SrvId, _State) ->
    continue.


%% @doc Called on new connectiom 
api_server_init(_NkPort, #{remote:=Remote}=State) ->
	lager:notice("New connection from ~s", [Remote]),
	{ok, State}.


%% @doc Called on connection stop
api_server_terminate(Reason, State) ->
	lager:notice("Stopped connection: ~p", [Reason]),
	{ok, State}.


%% @doc Called on login
api_server_login(#{<<"user">>:=User, <<"pass">>:=_Pass}=Data, _SessId, State) ->
	Meta = maps:get(<<"meta">>, Data, #{}),
    nkservice_api_server:start_ping(self(), 60),
    {true, User, State#{ws_test_meta=>Meta}};

api_server_login(_Data, _SessId, _State) ->
    continue.



%% @doc Called on any command
api_server_cmd(<<"test">>, <<"op1">>, Data, _TId, State) ->
	#{ws_test_meta:=_Meta} = State,
    {ok, #{res1=>Data}, State};

api_server_cmd(<<"test">>, <<"op2">>, Data, TId, State) ->
	Self = self(),
	spawn(
		fun() -> 
			timer:sleep(6000),
			nkservice_api_server:reply_ok(Self, TId, #{res2=>Data})
		end),
    {ack, State};

api_server_cmd(<<"test">>, <<"op3">>, Data, _TId, State) ->
	Self = self(),
	spawn(
		fun() -> 
			_ = nkservice_api_server:cmd(Self, server, core, op3_reply, #{you_sent=>Data})
		end),
    {ok, #{received=>ok}, State};

api_server_cmd(<<"test">>, <<"op4">>, Data, _TId, State) ->
	Self = self(),
	spawn(
		fun() -> 
			_ = nkservice_api_server:cmd(Self, jbg, core, <<"fun">>, #{you_sent=>Data})
		end),
    {ok, #{received=>ok}, State};

api_server_cmd(<<"test">>, _Cmd, _Data, _TId, State) ->
    {error, not_implemented, State};

api_server_cmd(_Class, _Cmd, _Data, _TId, _State) ->
    continue.

