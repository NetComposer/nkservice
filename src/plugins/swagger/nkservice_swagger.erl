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

%% @doc Swagger
%%
%% - Contents in priv/swagger copied directly from dist in
%%   https://github.com/swagger-api/swagger-ui
%% - Script updates index.html in nkservice_swagger_callbacks
%% - Must implement nkservice_swagger_get_spec/1


-module(nkservice_swagger).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').


