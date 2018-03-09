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

%% @doc Plugin implementation
-module(nkservice_jose).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([sign/4, verify/4]).
-export([luerl_sign/3, luerl_verify/3]).
-export([sample1/0, sample2/0]).

-define(LLOG(Type, Txt, Args),lager:Type("NkSERVICE JOSE "++Txt, Args)).

-dialyzer({nowarn_function, sample2/0}).
-dialyzer({nowarn_function, read_cert/1}).


%% ===================================================================
%% Types
%% ===================================================================


-type out_msg() :: binary() | map().

-type opts() ::
    #{
        key => binary(),        % Override key
        no_compact => boolean()
    }.



%% ===================================================================
%% API
%% ===================================================================

%% @doc Signs a request (anyone can decrypt it)
-spec sign(nkservice:id(), nkservice:module_id(), map(), opts()) ->
    {ok, out_msg()}.

sign(SrvId, PluginId, Msg, Opts) ->
    {JWK, JWS} = get_jws(SrvId, PluginId, Opts),
    Signed = jose_jwt:sign(JWK, JWS, Msg),
    case Opts of
        #{no_compact:=true} ->
            {ok, Signed};
        _ ->
            {_, Compact} = jose_jws:compact(Signed),
            {ok, Compact}
    end.


%% @doc Verifies if we signed the request
-spec verify(nkservice:id(), nkservice:module_id(), out_msg(), opts()) ->
    {true|false, map()} | map() | error.

verify(SrvId, PluginId, Term, Opts) ->
    {JWK, _JWS} = get_jws(SrvId, PluginId, Opts),
    NoCompact = maps:get(no_compact, Opts, false),
    case catch jose_jwt:verify(JWK, Term) of
        {'EXIT', _} ->
            error;
        Value when NoCompact ->
            Value;
        {true, {jose_jwt, Payload}, _} ->
            {true, Payload};
        {false, {jose_jwt, Payload}, _} ->
            {false, Payload}
    end.



%% ===================================================================
%% Luerl API
%% ===================================================================

%% @doc
luerl_sign(SrvId, PluginId, [Msg]) ->
    luerl_sign(SrvId, PluginId, [Msg, []]);

luerl_sign(SrvId, PluginId, [Msg, nil]) ->
    luerl_sign(SrvId, PluginId, [Msg, []]);

luerl_sign(SrvId, PluginId, [Msg, Opts]) when is_list(Msg), is_list(Opts) ->
    Msg2 = maps:from_list(Msg),
    Opts2 = case nklib_util:get_value(<<"key">>, Opts) of
        undefined ->
            #{};
        Key ->
            #{key => Key}
    end,
    {ok, Compact} = sign(SrvId, PluginId, Msg2, Opts2),
    [Compact];

luerl_sign(_SrvId, _PluginId, _Args) ->
    [nil, invalid_parameters].


%% @doc
luerl_verify(SrvId, PluginId, [Bin]) ->
    luerl_verify(SrvId, PluginId, [Bin, []]);

luerl_verify(SrvId, PluginId, [Bin, nil]) ->
    luerl_verify(SrvId, PluginId, [Bin, []]);

luerl_verify(SrvId, PluginId, [Bin, Opts]) when is_binary(Bin), is_list(Opts) ->
    Opts2 = case nklib_util:get_value(<<"key">>, Opts) of
        undefined ->
            #{};
        Key ->
            #{key => Key}
    end,
    case verify(SrvId, PluginId, Bin, Opts2) of
        {true, Body} ->
            [true, maps:to_list(Body)];
        {false, Body} ->
            [false, maps:to_list(Body)];
        error ->
            [nil, invalid_token]
    end;

luerl_verify(_SrvId, _PluginId, _Args) ->
    [error, invalid_parameters].





%% ===================================================================
%% Internal
%% ===================================================================

get_jws(SrvId, _PluginId, Opts) ->
    Key = case Opts of
        #{key:=Key0} ->
            Key0;
        _ ->
            nkservice_util:get_secret(SrvId, <<"jose_secret">>)
    end,
    % JSON Web Key
    JWK = #{
        <<"kty">> => <<"oct">>,
        <<"k">> => base64url:encode(Key)
    },
    % JSON Web Signature (JWS)
    JWS = #{
        <<"alg">> => <<"HS256">>
    },
    {JWK, JWS}.



%% ===================================================================
%% Samples
%% ===================================================================


sample1() ->
    % JSON Web Key (JWK)
    Key = crypto:strong_rand_bytes(32),
    JWK = #{
        <<"kty">> => <<"oct">>,
        <<"k">> => base64url:encode(Key)
    },
    % JSON Web Signature (JWS)
    JWS = #{
        <<"alg">> => <<"HS256">>
    },
    % JSON Web Token (JWT)
    JWT = #{
        <<"iss">> => <<"joe">>,
        <<"exp">> => 1300819380,
        <<"http://example.com/is_root">> => true
    },
    Signed = jose_jwt:sign(JWK, JWS, JWT),
    {_, CompactSigned} = jose_jws:compact(Signed),
    {true, _, _} = jose_jwt:verify(JWK, CompactSigned),
    {true, _, _} = jose_jwt:verify(JWK, Signed),

    Enc = jose_jwt:encrypt(JWK, #{<<"signed">>=>CompactSigned}),
    {_, {jose_jwt, #{<<"signed">>:=CompactSigned}}} = jose_jwt:decrypt(Key, Enc),
    ok.


sample2() ->
    RSAPrivateJWK = jose_jwk:from_pem_file(read_cert("rsa-2048.pem")),
    RSAPublicJWK  = jose_jwk:to_public(RSAPrivateJWK),

    %% Sign and Verify (defaults to PS256)
    Message = <<"my message">>,
    SignedPS256 = jose_jwk:sign(Message, RSAPrivateJWK),
    {true, Message, _} = jose_jwk:verify(SignedPS256, RSAPublicJWK),

    %% Sign and Verify (specify RS256)
    SignedRS256 = jose_jwk:sign(Message, #{ <<"alg">> => <<"RS256">> }, RSAPrivateJWK),
    {true, Message, _} = jose_jwk:verify(SignedRS256, RSAPublicJWK),

    %% Encrypt and Decrypt (defaults to RSA-OAEP with A128CBC-HS256)
    PlainText = <<"my plain text">>,
    EncryptedRSAOAEP = jose_jwk:block_encrypt(PlainText, RSAPublicJWK),
    {PlainText, _} = jose_jwk:block_decrypt(EncryptedRSAOAEP, RSAPrivateJWK),

    %% Encrypt and Decrypt (specify RSA-OAEP-256 with A128GCM)
    EncryptedRSAOAEP256 = jose_jwk:block_encrypt(PlainText, #{ <<"alg">> => <<"RSA-OAEP-256">>, <<"enc">> => <<"A128GCM">> }, RSAPublicJWK),
    {PlainText, _} = jose_jwk:block_decrypt(EncryptedRSAOAEP256, RSAPrivateJWK),

    % EC examples
    AlicePrivateJWK = jose_jwk:from_pem_file(read_cert("ec-secp256r1-alice.pem")),
    AlicePublicJWK  = jose_jwk:to_public(AlicePrivateJWK),
    BobPrivateJWK   = jose_jwk:from_pem_file(read_cert("ec-secp256r1-bob.pem")),
    BobPublicJWK    = jose_jwk:to_public(BobPrivateJWK),

    %% Sign and Verify (defaults to ES256)
    SignedES256 = jose_jwk:sign(Message, AlicePrivateJWK),
    {true, Message, _} = jose_jwk:verify(SignedES256, AlicePublicJWK),

    %% Encrypt and Decrypt (defaults to ECDH-ES with A128GCM)
    %%% Alice sends Bob a secret message using Bob's public key and Alice's private key
    AliceToBob = <<"For Bob's eyes only.">>,
    EncryptedECDHES = jose_jwk:box_encrypt(AliceToBob, BobPublicJWK, AlicePrivateJWK),
    %%% Only Bob can decrypt the message using his private key (Alice's public key is embedded in the JWE header)
    {AliceToBob, _} = jose_jwk:box_decrypt(EncryptedECDHES, BobPrivateJWK),
    ok.


read_cert(File) ->
    filename:join([code:priv_dir("nkservice"), "certs", File]).

