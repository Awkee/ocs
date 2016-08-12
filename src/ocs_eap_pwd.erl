%%% ocs_eap_pwd.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 SigScale Global Inc.
%%% @end
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc This library module implements the public API for the
%%% 	{@link //ocs. ocs} application.
%%%
%%% @reference <a href="http://tools.ietf.org/html/rfc5931">
%%% 	RFC5931 - EAP Authentication Using Only a Password</a>
%%%
-module(ocs_eap_pwd).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-export([h/1, prf/2, kdf/3]).

-include("ocs_eap_codec.hrl").

-spec h(Data :: binary()) -> binary().
%% @doc Implements a Random function, h which  maps a binary string of indeterminate
%% length onto a 32 bits fixed length binary.
h(Data) when is_binary(Data) ->
	crypto:hmac(sha256, <<0:256>>, Data).

-spec prf(Key :: binary(), Data :: binary()) -> binary().
%% @doc Implements a Pseudo-random function (PRF) which generates a random binary
%% string.
prf(Key, Data) when is_binary(Key), is_binary(Data) ->
	crypto:hmac(sha256, Key, Data).

 -spec kdf(Key :: binary(), Label :: string() | binary(), Length :: pos_integer())
		-> binary().
%% @doc Implements a Key derivation function (KDF) to stretch out a `Key' which is
%% binded with a `Lable' to a desired `Length'.
kdf(Key, Label, Length) when is_list(Label) ->
	kdf(Key, list_to_binary(Label), Length);
kdf(Key, Label, Length) when is_binary(Key), is_binary(Label),is_integer(Length) ->
	Data = list_to_binary([<<1:16>>, Label, <<Length:16>>]),
	K = prf(Key, Data),
	kdf(Key, Label, Length, 1, K, K).
%% @hidden
kdf(Key, Label, Length, I, K, Res) when size(Res) < (Length * 8) ->
	I1 = I + 1,
	Data = list_to_binary([K, <<I1:16>>, Label, <<Length:16>>]),
	K1 = prf(Key, Data),
	kdf(Key, Label, Length, 11, K1, <<Res/binary, K1/binary>>);
kdf(_, _, Length, _, _, Res) when size(Res) >= (Length * 8) ->
	binary:part(Res, 0, Length).

