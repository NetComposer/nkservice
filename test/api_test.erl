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
        api_server => "wss:all:9010, https://all:9010/rpc",
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


connect(User) ->
    Fun = fun ?MODULE:api_client_fun/2,
    Url = "nkapic://localhost:9010",
    Login = #{
        user_id => nklib_util:to_binary(User), 
        password=> <<"p1">>,
        meta => #{a=>User}
    },
    {ok, _, C} = nkservice_api_client:start(test, Url, Login, Fun, #{}),
    C.
 

user_list() ->
    cmd(core, user, list, #{}).


user_get(User) ->
    cmd(core, user, get, #{user => User}).

user_event(User) ->
    cmd(core, user, send_event, #{user=>User, type=>type1, body=>#{k=>v}}).    





event_get_subs() ->
    cmd(core, event, get_subscriptions, #{}).


event_subscribe() ->
    cmd(core, event, subscribe, #{class=>class1, body=>#{k=>v}}),
    cmd(core, event, subscribe, #{class=>class2, subclass=>s2}),
    cmd(core, event, subscribe, #{class=>class3, subclass=>s3, type=>t3}),
    cmd(core, event, subscribe, #{class=>class4, subclass=>s4, type=>t4, obj_id=>o4}).


event_unsubscribe() ->
    cmd(core, event, unsubscribe, #{class=>class1}),
    cmd(core, event, unsubscribe, #{class=>class2, subclass=>s2}),
    cmd(core, event, unsubscribe, #{class=>class3, subclass=>s3, type=>t3}),
    cmd(core, event, unsubscribe, #{class=>class4, subclass=>s4, type=>t4, obj_id=>o4}).

event_send(Class, Sub, Type, ObjId) ->
    cmd(core, event, send, #{class=>Class, subclass=>Sub, type=>Type, obj_id=>ObjId}).

event_send(T) ->
    Ev = case T of
        s1 -> #{class=>class1, subclass=>s1, type=>t1, obj_id=>o1, body=>#{k1=>v1}};
        s2a -> #{class=>class2, subclass=>s2, type=>t2, obj_id=>o2, body=>#{k2=>v2}};
        s2b -> #{class=>class2, subclass=>s3, type=>t2, obj_id=>o2, body=>#{k2=>v2}};
        s3a -> #{class=>class3, subclass=>s3, type=>t3, obj_id=>o3, body=>#{k3=>v3}};
        s3b -> #{class=>class3, subclass=>s3, type=>t4, body=>#{k3=>v3}};
        s4a -> #{class=>class4, subclass=>s4, type=>t4, obj_id=>o4, body=>#{k4=>v4}};
        s4b -> #{class=>class4, subclass=>s4, type=>t4, obj_id=>o5, body=>#{k4=>v4}}
    end,
    cmd(core, event, send, Ev).


session_event(SessId) ->
    cmd(core, session, send_event,#{session_id=>SessId, type=>type1, body=>#{k=>v}}).    

session_stop(SessId) ->
    cmd(core, session, stop, #{session_id => SessId}).

session_call(SessId) ->
    {ok, #{<<"k">> := <<"v">>}} = 
        cmd(core, session, cmd, 
            #{session_id=>SessId, class=>class1, cmd=>cmd1, data=>#{k=>v}}),
    {error, {100006, <<"Not implemented">>}} = 
        cmd(core, session, cmd, 
            #{session_id=>SessId, class=>class2, cmd=>cmd1, data=>#{k=>v}}),
    ok.


session_log(Source, Msg, Data) ->
    cmd(core, session, log, Data#{source=>Source, message=>Msg}).


get_client() ->
    [{_, Pid}|_] = nkservice_api_client:get_all(),
    Pid.


cmd(Class, Sub, Cmd, Data) ->
    Pid = get_client(),
    cmd(Pid, Class, Sub, Cmd, Data).

cmd(Pid, Class, Sub, Cmd, Data) ->
    nkservice_api_client:cmd(Pid, Class, Sub, Cmd, Data).




%% ===================================================================
%% Client fun
%% ===================================================================


api_client_fun(#api_req{class1=core, cmd1=event, data = Data}, UserData) ->
    Class = maps:get(<<"class">>, Data),
    Sub = maps:get(<<"subclass">>, Data, <<"*">>),
    Type = maps:get(<<"type">>, Data, <<"*">>),
    ObjId = maps:get(<<"obj_id">>, Data, <<"*">>),
    Body = maps:get(<<"body">>, Data, #{}),
    lager:notice("CLIENT event ~s:~s:~s:~s: ~p", [Class, Sub, Type, ObjId, Body]),
    {ok, #{}, UserData};

api_client_fun(#api_req{class1=class1, data=Data}=_Req, UserData) ->
    % lager:notice("API REQ: ~p", [lager:pr(_Req, ?MODULE)]),
    {ok, Data, UserData};

api_client_fun(_Req, UserData) ->
    % lager:error("API REQ: ~p", [lager:pr(_Req, ?MODULE)]),
    {error, not_implemented, UserData}.


%% ===================================================================
%% API callbacks
%% ===================================================================

%% @doc
api_server_syntax(#api_req{class1=test, cmd1=op1, data=_Data}, S, D, M) ->
    {S, D, M};

api_server_syntax(#api_req{class1=test, cmd1=op2, data=_Data}, S, D, M) ->
    {S, D, M};

api_server_syntax(#api_req{class1=test, cmd1=op3, data=_Data}, S, D, M) ->
    {S, D, M};

api_server_syntax(#api_req{class1=test, cmd1=op4, data=_Data}, S, D, M) ->
    {S, D, M};

api_server_syntax(_Req, _S, _D, _M) ->
    continue.


%% @doc
api_server_allow(_Req, State) ->
    {true, State}.


%% @doc Called on login
api_server_login(#{user_id:=User, password:=<<"p1">>, meta:=Meta}, State) ->
	{true, User, Meta, State};

api_server_login(_Data, _State) ->
    continue.


%% @doc Called on any command
api_server_cmd(#api_req{class1=test, cmd1=op1, data=Data}, State) ->
    {ok, #{res1=>Data}, State};

api_server_cmd(#api_req{class1=test, cmd1=op2, tid=TId, data=Data}, State) ->
	Self = self(),
	spawn(
		fun() -> 
			timer:sleep(6000),
			nkservice_api_server:reply_ok(Self, TId, #{res2=>Data})
		end),
    {ack, State};

api_server_cmd(#api_req{class1=test, cmd1=op3, data=Data}, State) ->
	Self = self(),
	spawn(
		fun() -> 
			_ = nkservice_api_server:cmd(Self, test, core, op3_reply, #{you_sent=>Data})
		end),
    {ok, #{received=>ok}, State};

api_server_cmd(_Req, _State) ->
    continue.

