%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Carlos Gonzalez Florido.  All Rights Reserved.
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

%% @doc Default callbacks
-module(nkservice_webserver_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([parse_url/1, make_listen/2]).


%% ===================================================================
%% Webserver & rest
%% ===================================================================



%% @private
parse_url({?MODULE, urls, Multi}) ->
    {ok, {?MODULE, urls, Multi}};

parse_url(Url) ->
    % Use protocol for transports and ports
    case nkpacket:multi_resolve(Url, #{resolve_type=>listen, protocol=>nkpacket_protocol_http}) of
        {ok, Multi} ->
            {ok, {?MODULE, urls, Multi}};
        {error, Error} ->
            {error, Error}
    end.


%% @doc
make_listen(SrvId, Endpoints) ->
    make_listen(SrvId, Endpoints, #{}).


%% @private
make_listen(_SrvId, [], Acc) ->
    Acc;
make_listen(SrvId, [#{id:=Id, url:={?MODULE, urls, Multi}}=Entry|Rest], Acc) ->
    Opts = maps:get(opts, Entry, #{}),
    Path = case Entry of
        #{file_path:=FilePath} ->
            FilePath;
        _ ->
            Priv = list_to_binary(code:priv_dir(nkservice)),
            <<Priv/binary, "/www">>
    end,
    Transps = make_listen_transps(SrvId, Id, Multi, Opts, Path, []),
    make_listen(SrvId, Rest, Acc#{Id => Transps}).


%% @private
make_listen_transps(_SrvId, _Id, [], _Opts, _Path, Acc) ->
    lists:reverse(Acc);

make_listen_transps(SrvId, Id, [{Transps, TranspOpts}|Rest], Opts, Path, Acc) ->
    Opts2 = maps:merge(TranspOpts, Opts),
    Opts3 = Opts2#{
        class => {nkservice_webserver, SrvId, Id},
        http_proto => {static, #{path=>Path, index_file=><<"index.html">>}}
    },
    Acc2 = Acc ++ [{Transps, Opts3}],
    make_listen_transps(SrvId, Id, Rest, Opts, Path, Acc2).


