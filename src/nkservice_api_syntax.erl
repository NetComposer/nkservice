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

%% @doc NkSERVICE external API

-module(nkservice_api_syntax).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([syntax/5]).


%% ===================================================================
%% Syntax
%% ===================================================================

%% @private
syntax(user, login, Syntax, Defaults, Mandatory) ->
    {
        Syntax#{
            user_id => binary, 
            password => binary,
            meta => map
        }, 
        Defaults, 
        Mandatory
    };

syntax(user, get, Syntax, Defaults, Mandatory) ->
    {Syntax#{user=>binary}, Defaults, [user|Mandatory]};

syntax(event, subscribe, Syntax, Defaults, Mandatory) ->
    {S, D, M} = syntax_events(Syntax, Defaults, Mandatory),
    {S#{body => any}, D, M};

syntax(event, unsubscribe, Syntax, Defaults, Mandatory) ->
    syntax_events(Syntax, Defaults, Mandatory);
  
syntax(event, send, Syntax, Defaults, Mandatory) ->
    {S, D, M} = syntax_events(Syntax, Defaults, Mandatory),
    {S#{body => any}, D, M};

syntax(user, send_event, Syntax, Defaults, Mandatory) ->
    {
        Syntax#{
            user => binary,
            type => binary,
            body => any
        },
        Defaults#{
            type => <<"*">>
        },
        [user|Mandatory]
    };

syntax(session, stop, Syntax, Defaults, Mandatory) ->
    {Syntax#{session_id=>binary}, Defaults, [session_id|Mandatory]};

syntax(session, send_event, Syntax, Defaults, Mandatory) ->
    {
        Syntax#{
            session_id => binary,
            type => binary,
            body => any
        },
        Defaults#{
            type => <<"*">>
        },
        [session_id|Mandatory]
    };

syntax(session, cmd, Syntax, Defaults, Mandatory) ->
    {
        Syntax#{
            session_id => binary,
            class => atom,
            subclass => atom,
            cmd => atom,
            data => any
        },
        Defaults#{subclass => core},
        [session_id, class, cmd|Mandatory]
    };

syntax(session, log, Syntax, Defaults, Mandatory) ->
    {
        Syntax#{
            source => binary,
            message => binary,
            full_message => binary,
            level => {integer, 1, 7},
            meta => any
        },
        Defaults#{level=>1},
        [source, message|Mandatory]
    };

syntax(_Sub, _Cmd, Syntax, Defaults, Mandatory) ->
    {Syntax, Defaults, Mandatory}.


%% @private
syntax_events(Syntax, Defaults, Mandatory) ->
    {
        Syntax#{
            class => binary,
            subclass => binary,
            type => binary,
            obj_id => binary,
            service => fun ?MODULE:parse_service/1
        },
        Defaults#{
            subclass => <<"*">>,
            type => <<"*">>,
            obj_id => <<"*">>
        },
        [class|Mandatory]
    }.



