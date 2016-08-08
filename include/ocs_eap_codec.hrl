%%% ocs_eap_codec.hrl
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
%%% 

%% Macro definitions for EAP Codes
-define(Request,				1).
-define(Response,				2).
-define(Success,				3).
-define(Faliure,				4).


%% Macro definitions for EAP data types
-define(Identity,						1).
-define(Notification,				2).
-define(Nak,							3).
-define(MD5Challenge,				4).
-define(OneTimePassword,			5).
-define(GenericTokenCard,			6).

-record(eap_packet,
			{code :: byte(),
			identifier :: byte(),
			data :: binary()}).
