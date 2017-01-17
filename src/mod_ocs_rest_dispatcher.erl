%%% mod_ocs_rest_dispatcher.erl
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
-module(mod_ocs_rest_dispatcher).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-export([do/1]).

-include_lib("inets/include/httpd.hrl"). 

-spec do(ModData) -> Result when
	ModData :: #mod{},
	Result :: {proceed, OldData} | {proceed, NewData} | {break, NewData} | done,
	OldData :: list(),
	NewData :: [{response,{StatusCode,Body}}] | [{response,{response,Head,Body}}]
			| [{response,{already_sent,StatusCode,Size}}],
	StatusCode :: integer(),
	Body :: list() | nobody | {Fun, Arg},
	Head :: [HeaderOption],
	HeaderOption :: {Option, Value} | {code, StatusCode},
	Option :: accept_ranges | allow
	| cache_control | content_MD5
	| content_encoding | content_language
	| content_length | content_location
	| content_range | content_type | date
	| etag | expires | last_modified
	| location | pragma | retry_after
	| server | trailer | transfer_encoding,
	Value :: string(),
	Size :: term(),
	Fun :: fun((Arg) -> sent| close | Body),
	Arg :: [term()].
%% @doc Erlang web server API callback function.
do(#mod{request_uri = Uri, data = Data} = ModData) ->
	case string:tokens(Uri, "/") of
		["ocs", "v1", _Resource] ->
			{proceed, Data};
		["ocs", "v1", _Resource, _Identity] ->
			{proceed, Data};
		_ ->
			dispatch(ModData)
end.

%% @hidden
dispatch(#mod{socket = Socket, socket_type = SockType, data = Data,
		config_db = ConfigDb, request_uri = Uri} = ModData) ->
	Path = mod_alias:path(Data, ConfigDb, Uri),
	send_response(Socket, SockType, Path, ModData). 

%% @hidden
send_response(_Socket, _SockType, Path, #mod{config_db = ConfigDb,
		data = Data} = ModData) ->
	case file:open(Path,[raw,binary]) of
		{ok, FileDescriptor} ->
			{ok, FileContent} = file:read_file(Path),
			{FileInfo, LastModified} = get_modification_date(Path),
			Suffix = httpd_util:suffix(Path),
			MimeType = httpd_util:lookup_mime_default(ConfigDb, Suffix, "text/plain"),
			Size = integer_to_list(FileInfo#file_info.size),
			Headers = [{content_type, MimeType},
					{etag, httpd_util:create_etag(FileInfo)},
					{content_length, Size}|LastModified],
			send(ModData, 200, Headers, FileContent),
			file:close(FileDescriptor),
			{proceed,[{response, {already_sent,200, FileInfo#file_info.size}},
			{mime_type,MimeType} | Data]};
		{error, Reason} ->
			Status = httpd_file:handle_error(Reason, "open", ModData, Path),
			{proceed, [{status, Status} | Data]}
	end.

%% @hidden
send(#mod{socket = Socket, socket_type = SocketType} = ModData,
     StatusCode, Headers, ResponseBody) ->
    httpd_response:send_header(ModData, StatusCode, Headers),
    httpd_socket:deliver(SocketType, Socket, ResponseBody).

%% @hidden
get_modification_date(Path)->
    {ok, FileInfo0} = file:read_file_info(Path), 
    LastModified = 
	case catch httpd_util:rfc1123_date(FileInfo0#file_info.mtime) of
	    Date when is_list(Date) -> [{last_modified, Date}];
	    _ -> []
	end,
    {FileInfo0, LastModified}.

