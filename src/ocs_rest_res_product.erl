%%% ocs_rest_res_balance.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2017 SigScale Global Inc.
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
-module(ocs_rest_res_product).
-copyright('Copyright (c) 2016 - 2017 SigScale Global Inc.').

-export([content_types_accepted/0, content_types_provided/0]).

-export([add_product/1]).

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

-spec add_product(ReqData) -> Result when
	ReqData	:: [tuple()],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 500 .
%% @doc Respond to `POST /catalogManagement/v1/product' and
%% add a new `product'
add_product(ReqData) ->
	try
		{struct, Object} = mochijson:decode(ReqData),
		{_, _Name} = lists:keyfind("name", 1, Object),
		IsBundle = case lists:keyfind("isBundle", 1, Object) of
			{"isBundle", "true"} -> true;
			_ -> false
		end,
		Status  = case lists:keyfind("lifecycleStatus", 1, Object) of
			{_, FindStatus} ->
				find_status(FindStatus);
			false ->
				"active"
		end
		{_, ProdOfPriceObj} = lists:keyfind("productOfferingPrice", 1, Object),
		{array, ProdOfPrice} = mochijson:decode(ProdOfPriceObj),
		Product = product_offering_price(ProdOfPrice, IsBundle, Status),
		Descirption = proplists:get_value("description", Object, ""),
		case add_product1(Prodcut) of
			ok ->
				add_product2(Object);
			{error, StatusCode} ->
				{error, StatusCode}
		end
	catch
		_:_ ->
			{error, 400}
	end.
%% @hidden
add_product1(Products) ->
	F2 = fun(Product) ->
		ok = mnesia:write(product, Product, write)
	end,
	F1 = fun() ->
		lists:foreach(F2, Products)
	end,
	case mnesia:transaction(F1) of
		{atomic, ok} ->
			ok;
		{aborted, _} ->
			{error, 500}
	end.
%% @hidden
add_product2(JsonResponse) ->
	Id = {id, ""},
	Body = {struct, [Id | JsonResponse]},
	Location = "/catalogManagement/v1/product", %% ++ id
	Headers = [{location, Location}],
	{ok, Headers, Body}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec product_offering_price(POfPrice, IsBundle, Status) -> Result when
	POfPrice	:: list(),
	IsBundle	:: boolean(),
	Status	:: product_status(),
	Result 	:: Products | {error, StatusCode},
	Products	:: [#product{}],
	StatusCode	:: 400.
%% @doc construct list of product
%% @private
product_offering_price(POfPrice, IsBundle, Status) ->
	try
		F = fun(ProductJson, AccIn) ->
				{struct, Object} = mochijson:decode(ProductJson),
				{_, Name} = lists:keyfind("name", 1, Object),
				{_, ValidFor} = lists:keyfind("validFor", 1, Object),
				{struct, VForObject1} = mochijson:decode(ValidFor),
				{_, _STime} = lists:keyfind("startDateTime", 1, VForObject1),
				{_, _ETime} = lists:keyfind("endDateTime", 1, VForObject1),
				{_, PriceTypeS} = lists:keyfind("priceType", 1, Object),
				PriceType = price_type(PriceTypeS),
				{_, UnitOfMesasure} = lists:keyfind("unitOfMeasure", 1, Object),
				{_, PriceObject} = lists:keyfind("price", 1, Object),
				TaxPAmount = proplists:get_value("taxIncludedAmount", PriceObject, ""),
				_DutyFreeAmount = proplists:get_value("dutyFreeAmount", PriceObject, ""),
				_TaxRate = proplists:get_value("taxRate", PriceObject, ""),
				_CurrencyCode = proplists:get_value("currencyCode", PriceObject, ""),
				_RecurringChargePeriod = proplists:get_value("recurringChargePeriod", Object, ""),
				Descirption = proplists:get_value("description", Object, ""),
				Product = #product{name = Name, is_bundle = IsBundle, status = Status,
					units = UnitOfMesasure, price = TaxPAmount, description = Descirption,
					price_type = PriceType},
				[Product | AccIn]
		end,
		AccOut = lists:foldl(F, [], POfPrice),
		lists:reverse(AccOut)
	catch
		_:_ ->
			{error, 400}
	end.

-spec find_status(StringStatus) -> Status when
	StringStatus	:: string(),
	Status			:: product_status().
%% @doc return life cycle status of the product
%% @private
find_status("created") ->
	created;
find_status("aborted") ->
	aborted;
find_status("cancelled") ->
	cancelled;
find_status("active") ->
	active;
find_status("pending_active") ->
	pending_active;
find_status("suspended") ->
	suspended;
find_status("terminate") ->
	terminate;
find_status("pending_terminate") ->
	pending_terminate.

-spec price_type(StringPriceType) -> PriceType when
	StringPriceType :: string(),
	PriceType		 :: recurring | one_time | usage.
%% @private
price_type("recurring") ->
	recurring;
price_type("one_time") ->
	one_time;
price_type("usage") ->
	usage.

-spec iso8601(MilliSeconds) -> Result
	when
		MilliSeconds :: pos_integer(),
		Result :: string().
%% @doc Convert timestamp to ISO 8601 format date and time.
iso8601(MilliSeconds) when is_integer(MilliSeconds) ->
	{{Year, Month, Day}, {Hour, Minute, Second}} = date(MilliSeconds),
	DateFormat = "~4.10.0b-~2.10.0b-~2.10.0b",
	TimeFormat = "T~2.10.0b:~2.10.0b:~2.10.0b.~3.10.0bZ",
	Chars = io_lib:fwrite(DateFormat ++ TimeFormat,
			[Year, Month, Day, Hour, Minute, Second, MilliSeconds rem 1000]),
	lists:flatten(Chars).

