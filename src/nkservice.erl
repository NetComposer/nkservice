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

-module(nkservice).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export_type([id/0, name/0, spec/0, class/0, info/0]).
-export([make_id/1]).

%% ===================================================================
%% Types
%% ===================================================================

-type name() :: term().

-type id() :: atom().

-type spec() :: 
	#{
		class => class(),
		plugins => [module()],
        callback => [module()],
        transports => string() | binary() | [string() | binary()]
	}.

-type class() :: atom().

-type info() ::
    #{
        class => class(),
        status => ok | starting | error,
        error => binary(),
        pid => pid()
    }.


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Generates a internal name (an atom()) for any term
-spec make_id(nkservice:name()) ->
    id().

make_id(Name) ->
    list_to_atom(
        string:to_lower(
            case binary_to_list(nklib_util:hash36(Name)) of
                [F|Rest] when F>=$0, F=<$9 -> [$A+F-$0|Rest];
                Other -> Other
            end)).
