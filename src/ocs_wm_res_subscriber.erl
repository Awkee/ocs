%%% ocs_wm_res_subscriber.erl
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
%%% @doc This {@link //webmachine. webmachine} callback module
%%% 	implements resource handlers for the `/subscriber' URI within the
%%% 	{@link //oss_gw. oss_gw} application's REST API.
%%% @reference WebMachine Wiki
%%% 	<a href="https://github.com/webmachine/webmachine/wiki/Resource-Functions">
%%% 	Resource Functions</a>.
%%%
-module(ocs_wm_res_subscriber).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

% export the webmachine callbacks
-export([init/1,
		allowed_methods/2,
		content_types_accepted/2,
		content_types_provided/2,
		post_is_create/2,
		create_path/2 ]).

-include("ocs_wm.hrl").

-record(state,{}).

%%----------------------------------------------------------------------
%%  webmachine callbacks
%%----------------------------------------------------------------------

-spec init(Config :: proplists:proplist()) ->
	{ok | {trace, Dir :: file:filename()}, Context :: state()}.
%% @doc The dispatcher calls this function for every request to the resource.
init(Config) ->
	Result = case proplists:lookup(trace, Config) of
		{trace, false} ->
			ok;
		{trace, File} when is_list(File) ->
			{trace, File};
		none ->
			ok
	end,
	{Result, #state{}}.

-spec allowed_methods(rd(), state()) -> {[Method], rd(), state()}
		when Method :: 'GET' | 'HEAD' | 'PUT' | 'POST' | 'DELETE' | 'OPTIONS'.
%% @doc If a Method not in this list is requested, then a
%% 	`405 Method Not Allowed' will be sent.
allowed_methods(ReqData, Context) ->
	{['POST', 'GET', 'HEAD', 'DELETE'], ReqData, Context}.

-spec content_types_accepted(ReqData :: rd(), Context :: state()) ->
	{[{MediaType :: string(), Handler :: atom()}],
	ReqData :: rd(), Context :: state()}.
%% @doc Content negotiation for request body.
content_types_accepted(ReqData, Context) ->
	case wrq:method(ReqData) of
		'POST' ->
			{[{"application/json",
					add_subscriber}], ReqData, Context};
		'GET' ->
			{[], ReqData, Context};
		'HEAD' ->
			{[], ReqData, Context};
		'DELETE' ->
			{[], ReqData, Context}
	end.

-spec content_types_provided(ReqData :: rd(), Context :: state()) ->
	{[{MediaType :: string(), Handler :: atom()}],
	ReqData :: rd(), Context :: state()}.
%% @doc Content negotiation for response body.
content_types_provided(ReqData, Context) ->
	case wrq:method(ReqData) of
		'POST' ->
			{[{"application/hal+json", add_router}], ReqData, Context};
		Method when Method == 'GET'; Method == 'HEAD' ->
			case {wrq:path_info(router, ReqData), wrq:req_qs(ReqData)} of
				{_, [_|_]} ->
					{[], ReqData, Context}
			end
	end.

-spec post_is_create(ReqData :: rd(), Context :: state()) ->
	{Result :: boolean(), ReqData :: rd(), Context :: state()}.
%% @doc If POST requests put content into a (potentially new) resource.
post_is_create(ReqData, Context) ->
	{true, ReqData, Context}.

-spec create_path(ReqData :: rd(), Context :: state()) ->
	{Path :: string(), ReqData :: rd(), Context :: state()}.
%% @doc Called on a `POST' request if {@link post_is_create/2} returns true.
create_path(ReqData, Context) ->
	Body = wrq:req_body(ReqData),
	try
		{struct, Object} = mochijson:decode(Body),
		{true, ReqData, Context}
	catch
		_Error ->
			{{halt, 400}, ReqData, Context}
	end.
