%%% ocs_rest_res_subscriber.erl
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
%%% @doc This library module implements resource handling functions
%%% 	for a REST server in the {@link //ocs. ocs} application.
%%%
-module(ocs_rest_res_subscriber).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

-export([content_types_accepted/0,
				content_types_provided/0,
				perform_get/1,
				perform_get_all/0,
				perform_post/1,
				perform_patch/2,
				perform_delete/1]).

-include_lib("radius/include/radius.hrl").
-include("ocs.hrl").

-spec content_types_accepted() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations accepted.
content_types_accepted() ->
	["application/json"].

-spec content_types_provided() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations available.
content_types_provided() ->
	["application/json"].

-spec perform_get(Id) -> Result
	when
		Id :: string(),
		Result :: {ok, Headers :: [string()],
				Body :: iolist()} | {error, ErrorCode :: integer()}.
%% @doc Body producing function for `GET /ocs/v1/subscriber/{id}'
%% requests.
perform_get(Id) ->
	case ocs:find_subscriber(Id) of
		{ok, PWBin, Attributes, Balance, Enabled} ->
			Password = binary_to_list(PWBin),
			JSAttributes = radius_to_json(Attributes),
			AttrObj = {array, JSAttributes},
			RespObj = [{id, Id}, {href, "/ocs/v1/subscriber/" ++ Id},
				{password, Password}, {attributes, AttrObj}, {balance, Balance},
				{enabled, Enabled}],
			JsonObj  = {struct, RespObj},
			Body = mochijson:encode(JsonObj),
			{ok, [], Body};
		{error, _Reason} ->
			{error, 404}
	end.

-spec perform_get_all() -> Result
	when
		Result :: {ok, Headers :: [string()],
				Body :: iolist()} | {error, ErrorCode :: integer()}.
%% @doc Body producing function for `GET /ocs/v1/subscriber'
%% requests.
perform_get_all() ->
	case ocs:get_subscribers() of
		{error, _} ->
			{error, 404};
		Subscribers ->
			Response = perform_get_all1(Subscribers),
			Body  = mochijson:encode(Response),
			Headers = [{content_type, "application/json"}],
			{ok, Headers, Body}
	end.
%% @hidden
perform_get_all1(Subscribers) ->
			F = fun(#subscriber{name = Id, password = Password,
					attributes = Attributes, balance = Balance, enabled = Enabled}, Acc) ->
				JSAttributes = radius_to_json(Attributes),
				AttrObj = {array, JSAttributes},
				RespObj = [{struct, [{id, Id}, {href, "/ocs/v1/subscriber/" ++ binary_to_list(Id)},
					{password, Password}, {attributes, AttrObj}, {balance, Balance},
					{enabled, Enabled}]}],
				RespObj ++ Acc
			end,
			JsonObj = lists:foldl(F, [], Subscribers),
			{array, JsonObj}.

-spec perform_post(RequestBody) -> Result 
	when 
		RequestBody :: list(),
		Result :: {Location :: string(), Body :: iolist()} | {error, ErrorCode :: integer()}.
%% @doc Respond to `POST /ocs/v1/subscriber' and add a new `subscriber'
%% resource.
perform_post(RequestBody) ->
	try 
		{struct, Object} = mochijson:decode(RequestBody),
		{_, Id} = lists:keyfind("id", 1, Object),
		Password = case lists:keyfind("password", 1, Object) of
			{_, PWD} ->
				PWD;
			false ->
				ocs:generate_password()
		end,
		RadAttributes = case lists:keyfind("attributes", 1, Object) of
			{_, {array, JsonObjList}} ->
				json_to_radius(JsonObjList);
			false ->
				[]
		end,
		{_, Balance} = lists:keyfind("balance", 1, Object),
		{_, EnabledStatus} = lists:keyfind("enabled", 1, Object),
		perform_post1(Id, Password, RadAttributes, Balance, EnabledStatus)
	catch
		_Error ->
			{error, 400}
	end.
%% @hidden
perform_post1(Id, null, RadAttributes, Balance, EnabledStatus) ->
	perform_post1(Id, "", RadAttributes, Balance, EnabledStatus);
perform_post1(Id, Password, RadAttributes, Balance, EnabledStatus) ->
	try
	case catch ocs:add_subscriber(Id, Password, RadAttributes, Balance, EnabledStatus) of
		ok ->
			Attributes = {array, radius_to_json(RadAttributes)},
			RespObj = [{id, Id}, {href, "/ocs/v1/subscriber/" ++ Id},
				{password, Password}, {attributes, Attributes}, {balance, Balance},
				{enabled, EnabledStatus}],
			JsonObj  = {struct, RespObj},
			Body = mochijson:encode(JsonObj),
			Location = "/ocs/v1/subscriber/" ++ Id,
			{Location, Body};
		{error, _Reason} ->
			{error, 400}
	end catch
		throw:_ ->
			{error, 400}
	end.

-spec perform_patch(Id, ReqBody) -> Result
	when
		Id :: list(),
		ReqBody :: list(),
		Result :: {body, Body :: iolist()} | {error, ErrorCode :: integer()} .
%% @doc	Respond to `PATCH /ocs/v1/subscriber/{id}' request and
%% Updates a existing `subscriber''s password or attributes. 
perform_patch(Id, ReqBody) ->
	case ocs:find_subscriber(Id) of
		{ok, CurrentPwd, CurrentAttr, Bal, Enabled} ->
			try 
				{struct, Object} = mochijson:decode(ReqBody),
				{_, Type} = lists:keyfind("update", 1, Object),
				{Password, RadAttr} = case Type of
					"attributes" ->
						{_, {array, AttrJs}} = lists:keyfind("attributes", 1, Object),
						NewAttributes = json_to_radius(AttrJs),
						{_, Balance} = lists:keyfind("balance", 1, Object),
						{_, EnabledStatus} = lists:keyfind("enabled", 1, Object),
						ocs:update_attributes(Id, Balance, NewAttributes, EnabledStatus),
						{CurrentPwd, NewAttributes};
					"password" ->
						{_, NewPassword } = lists:keyfind("newpassword", 1, Object),
						ocs:update_password(Id, NewPassword),
						{NewPassword, CurrentAttr}
				end,
				Attributes = {array, radius_to_json(RadAttr)},
				RespObj =[{id, Id}, {href, "/ocs/v1/subscriber/" ++ Id},
					{password, Password}, {attributes, Attributes}, {balance, Bal},
					{enabled, Enabled}],
				JsonObj  = {struct, RespObj},
				RespBody = mochijson:encode(JsonObj),
				{body, RespBody}
			catch
				throw : _ ->
					{error, 400}
			end;
		{error, _Reason} ->
			{error, 404}
	end.

-spec perform_delete(Id) -> ok 
	when
		Id :: list().
%% @doc Respond to `DELETE /ocs/v1/subscriber/{id}' request and deletes
%% a `subscriber' resource. If the deletion is succeeded return true.
perform_delete(Id) ->
	ok = ocs:delete_subscriber(Id),
	ok.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

%% @hidden
json_to_radius(JsonObjList) ->
	json_to_radius(JsonObjList, []).
%% @hidden
json_to_radius([{struct, [{"name", "ascendDataRate"} | VendorSpecific]} | T], Acc) ->
	case vendor_specific(VendorSpecific) of
		[] ->
			json_to_radius(T, Acc) ;
		Attribute ->
			json_to_radius(T, [Attribute | Acc])
	end;
json_to_radius([{struct, [{"name", "ascendXmitRate"} | VendorSpecific]} | T], Acc) ->
	case vendor_specific(VendorSpecific) of
		[] ->
			json_to_radius(T, Acc);
		Attribute ->
			json_to_radius(T, [Attribute | Acc])
	end;
json_to_radius([{struct,[{"name","sessionTimeout"}, {"value", V}]} | T], Acc) when V == null; V == "" ->
	json_to_radius(T, Acc);
json_to_radius([{struct,[{"name","sessionTimeout"}, {"value", V}]} | T], Acc) ->
	Attribute = {?SessionTimeout, V},
	json_to_radius(T, [Attribute | Acc]);
json_to_radius([{struct,[{"name","acctInterimInterval"}, {"value", V}]} | T], Acc) when V == null; V == ""->
	json_to_radius(T,Acc);
json_to_radius([{struct,[{"name","acctInterimInterval"}, {"value", V}]} | T], Acc) ->
	Attribute = {?AcctInterimInterval, V},
	json_to_radius(T, [Attribute | Acc]);
json_to_radius([{struct,[{"name","class"}, {"value", V}]} | T], Acc) when V == null; V == "" ->
	json_to_radius(T, Acc);
json_to_radius([{struct,[{"name","class"}, {"value", V}]} | T], Acc) ->
	Attribute = {?Class, V},
	json_to_radius(T, [Attribute | Acc]);
json_to_radius([], Acc) ->
	Acc.

%% @hidden
radius_to_json(RadiusAttributes) ->
	radius_to_json(RadiusAttributes, []).
%% @hidden
radius_to_json([{?VendorSpecific, {?Ascend, {?AscendDataRate, _}}} = H | T], Acc) ->
	{struct, Values} = vendor_specific(H),
	Attribute = {struct, [{"name", "ascendDataRate"} | Values]},
	radius_to_json(T, [Attribute | Acc]);
radius_to_json([{?VendorSpecific, {?Ascend, {?AscendXmitRate, _}}} = H | T], Acc) ->
	{struct, Values} = vendor_specific(H),
	Attribute = {struct, [{"name", "ascendXmitRate"} | Values]},
	radius_to_json(T, [Attribute | Acc]);
radius_to_json([{?SessionTimeout, V} | T], Acc) ->
	Attribute = {struct, [{"name", "sessionTimeout"}, {"value",  V}]},
	radius_to_json(T, [Attribute | Acc]);
radius_to_json([{?AcctInterimInterval, V} | T], Acc) ->
	Attribute = {struct, [{"name", "acctInterimInterval"}, {"value", V}]},
	radius_to_json(T, [Attribute | Acc]);
radius_to_json([{?Class, V} | T], Acc) ->
	Attribute = {struct, [{"name", "class"}, {"value", V}]},
	radius_to_json(T, [Attribute | Acc]);
radius_to_json([], Acc) ->
	Acc.

%% @hidden
vendor_specific(AttrJson) when is_list(AttrJson) ->
	{_, Type} = lists:keyfind("type", 1, AttrJson),
	{_, VendorID} = lists:keyfind("vendorId", 1, AttrJson),
	{_, Key} = lists:keyfind("vendorType", 1, AttrJson),
	case lists:keyfind("value", 1, AttrJson) of
		{_, null} ->
			[];
		{_, Value} ->
			{Type, {VendorID, {Key, Value}}}
	end;
vendor_specific({Type, {VendorID, {VendorType, Value}}}) ->
	AttrObj = [{"type", Type},
				{"vendorId", VendorID},
				{"vendorType", VendorType},
				{"value", Value}],
	{struct, AttrObj}.

