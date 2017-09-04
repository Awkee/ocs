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
-export([get_product/1]).

-include_lib("radius/include/radius.hrl").
-include("ocs.hrl").

-spec content_types_accepted() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations accepted.
content_types_accepted() ->
	[	"application/json"].

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
		Name = prod_name(erlang_term, Object),
		IsBundle = prod_isBundle(erlang_term, Object),
		Status = prod_status(erlang_term, Object),
		Descirption = prod_description(erlang_term, Object),
		case prod_offering_price(erlang_term, Object) of
			{error, StatusCode} ->
				{error, StatusCode};
			Price ->
				Product = #product{price = Price, name = Name, is_bundle = IsBundle,
				status = Status, description = Descirption},
				case add_product1(Product) of
					ok ->
						add_product2(Name, Object);
					{error, StatusCode} ->
						{error, StatusCode}
				end
		end
	catch
		_:_ ->
			{error, 400}
	end.
%% @hidden
add_product1(Products) ->
	F1 = fun() ->
		ok = mnesia:write(product, Products, write)
	end,
	case mnesia:transaction(F1) of
		{atomic, ok} ->
			ok;
		{aborted, _} ->
			{error, 500}
	end.
%% @hidden
add_product2(ProdId, JsonResponse) ->
	Id = {id, ProdId},
	Json = {struct, [Id | JsonResponse]},
	Body = mochijson:encode(Json),
	Location = "/catalogManagement/v1/product/" ++ ProdId,
	Headers = [{location, Location}],
	{ok, Headers, Body}.

-spec get_product(ProdID) -> Result when
	ProdID	:: string(),
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /productInventoryManagement/v1/{id}' and
%% retrieve a `product' details
get_product(ProductID) ->
	F = fun() ->
		case mnesia:read(product, ProductID) of
			[Product] ->
				Product;
			[] ->
				throw(not_found)
		end
	end,
	case mnesia:transaction(F) of
		{atomic, Prod} ->
			get_product1(Prod);
		{aborted, {throw, not_found}} ->
			{error, 404};
		{aborted, _} ->
			{error, 500}
	end.
%% @hidden
get_product1(Prod) ->
	ID = prod_id(json, Prod),
	Descirption = prod_description(json, Prod),
	Href = prod_href(json, Prod),
	IsBundle = prod_isBundle(json, Prod),
	Name = prod_name(json, Prod),
	Status = prod_status(json, Prod),
	OfferPrice = prod_offering_price(json, Prod),
	Json = {struct, [ID, Descirption, Href, IsBundle, Name, Status, OfferPrice]},
	Body = mochijson:encode(Json),
	Headers = [{content_type, "application/json"}],
	{ok, Headers, Body}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------
-spec prod_id(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: string() | tuple().
%% @private
prod_id(json, Product) ->
	{"id", Product#product.name}.

-spec prod_name(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product		:: list() | #product{},
		Result	:: string() | tuple().
%% @private
prod_name(erlang_term, Product) ->
	{_, Name} = lists:keyfind("name", 1, Product),
	Name;
prod_name(json, Prod) ->
	{"name", Prod#product.name}.

-spec prod_isBundle(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: boolean() | tuple().
%% @private
prod_isBundle(erlang_term, Product) ->
	case lists:keyfind("isBundle", 1, Product) of
		{"isBundle", "true"} -> true;
		_ -> false
	end;
prod_isBundle(json, Product) ->
	{"is_bundle", Product#product.is_bundle}.

-spec prod_status(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: string() | tuple().
%% @private
prod_status(erlang_term, Product) ->
	case lists:keyfind("lifecycleStatus", 1, Product) of
		{_, FindStatus} ->
			find_status(FindStatus);
		false ->
			"active"
	end;
prod_status(json, Product) ->
	{"status", Product#product.status}.

-spec prod_description(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: undefined | string() | tuple().
%% @private
prod_description(erlang_term, Product) ->
	proplists:get_value("description", Product, undefined);
prod_description(json, Product) ->
	{"description", Product#product.description}.

-spec prod_href(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: undefined | string() | tuple().
%% @private
prod_href(json, Product) ->
	{"href", "/product/product/" ++ Product#product.name}.

-spec prod_offering_price(Prefix, Product) -> Result
	when
		Prefix	:: erlang_term | json,
		Product	:: list() | #product{},
		Result	:: [#price{}] | list() | {error, Status},
		Status	:: 400.
%% @doc construct list of product
%% @private
prod_offering_price(erlang_term, []) ->
	{error, 400};
prod_offering_price(erlang_term, Json) ->
	{_, {array, ProdOfPrice}} = lists:keyfind("productOfferingPrice", 1, Json),
	po_price(erlang_term, ProdOfPrice, []);
prod_offering_price(json, Product) ->
	ProdOfPrice = po_price(json, Product#product.price, []),
	{"productOfferingPrice", {array, ProdOfPrice}}.

-spec po_price(Prefix, ProductOfPrice, Prices) -> Result
	when
		Prefix	:: erlang_term | json,
		ProductOfPrice	:: list() | [#price{}],
		Prices	::	list(),
		Result	:: [#price{}] | list() | {error, Status},
		Status	:: 400.
%% @hidden
po_price(erlang_term, [], Prices) ->
	Prices;
po_price(erlang_term, [{struct, Object} | T], Prices) ->
	try
		ProdName = prod_price_name(erlang_term, Object),
		{ProdSTime, ProdETime} = prod_price_vf(erlang_term, Object),
		ProdPriceType = prod_price_type(erlang_term, Object),
		{_, {struct, ProdPriceObj}} = lists:keyfind("price", 1, Object),
		{_, ProdAmount} = lists:keyfind("taxIncludedAmount", 1, ProdPriceObj),
		{_, CurrencyCode} = lists:keyfind("currencyCode", 1, ProdPriceObj),
		{_, RCPeriodS} = lists:keyfind("recurringChargePeriod", 1, Object),
		ProdDescirption = proplists:get_value("description", Object, ""),
		ProdUOMesasure = proplists:get_value("unitOfMeasure", Object, ""),
		ProdValidity = validity_period(ProdSTime, ProdETime),
		if
			ProdValidity =/= {error, format_error} ->
				{ProdUnits, ProdSize} = product_unit_of_measure(ProdUOMesasure),
				Size = product_size(ProdUnits, octets, ProdSize),
				RCPeriod = recurring_charge_period(RCPeriodS),
				Price1 = #price{name = ProdName, description = ProdDescirption,
				type = ProdPriceType, units = ProdUnits, size = Size,
					currency = CurrencyCode, period = RCPeriod, validity = ProdValidity,
					amount = ProdAmount},
				case lists:keyfind("productOfferPriceAlteration", 1, Object) of
					false ->
						po_price(erlang_term, T, [Price1 | Prices]);
					{_, {struct, ProdAlterObj}} ->
						case po_alteration(erlang_term, ProdAlterObj) of
							{error, Status} ->
								{error, Status};
							Alteration ->
								Price2 = Price1#price{alteration = Alteration},
								po_price(erlang_term, T, [Price2 | Prices])
						end
				end;
			true ->
				{error, 400}
		end
	catch
		_:_ ->
			{error, 400}
	end;
po_price(json, [Price | T], Prices) when is_record(Price, price) ->
	todo.


-spec po_alteration(Prefix, ProdAlterObj) -> Result
	when
		Prefix	:: erlang_term | json,
		ProdAlterObj :: list(),
		Result	:: #alteration{} | {error, Status},
		Status	:: 400.
%% @private
po_alteration(erlang_term, ProdAlterObj) ->
	try
		{_, ProdAlterName} = lists:keyfind("name", 1, ProdAlterObj),
		{_, {struct, ProdAlterVFObj}} = lists:keyfind("validFor", 1, ProdAlterObj),
		{_, ProdAlterSTimeISO} = lists:keyfind("startDateTime", 1, ProdAlterVFObj),
		{_, ProdAlterPriceTypeS} = lists:keyfind("priceType", 1, ProdAlterObj),
		{_, ProdAlterUOMeasure} = lists:keyfind("unitOfMeasure", 1, ProdAlterObj),
		{_, {struct, ProdAlterPriceObj}} = lists:keyfind("price", 1, ProdAlterObj),
		{_, ProdAlterAmount} = lists:keyfind("taxIncludedAmount", 1,  ProdAlterPriceObj),
		ProdAlterDescirption = proplists:get_value("description", ProdAlterObj, ""),
		{ProdAlterUnits, ProdAlterSize} = product_unit_of_measure(ProdAlterUOMeasure),
		AlterSize = product_size(ProdAlterUnits, octets, ProdAlterSize),
		_ProdAlterSTime = ocs_rest:timestamp(ProdAlterSTimeISO),
		ProdAlterPriceType = price_type(ProdAlterPriceTypeS),
		#alteration{name = ProdAlterName, description = ProdAlterDescirption,
			units = ProdAlterUnits, size = AlterSize, amount = ProdAlterAmount}
	catch
		_:_ ->
			{error, 400}
	end.

-spec prod_price_name(Prefix, Price) -> Result
	when
		Prefix	:: erlang_term | json,
		Price		:: list() | #price{},
		Result	:: string() | tuple().
%% @private
prod_price_name(erlang_term, Price) ->
	{_, Name} = lists:keyfind("name", 1, Price),
	Name;
prod_price_name(json, Price) ->
	{"name", Price#price.name}.

-spec prod_price_vf(Prefix, Price) -> Result
	when
		Prefix	:: erlang_term | json,
		Price		:: list() | #price{},
		Result	:: tuple().
%% @private
prod_price_vf(erlang_term, Price) ->
	{_,  {struct, VFObj}} = lists:keyfind("validFor", 1, Price),
	{_, ProdSTime} = lists:keyfind("startDateTime", 1, VFObj),
	{_, ProdETime} = lists:keyfind("endDateTime", 1, VFObj),
	{ProdSTime, ProdETime}.

-spec prod_price_type(Prefix, Price) -> Result
	when
		Prefix	:: erlang_term | json,
		Price		:: list() | #price{},
		Result	:: atom() | tuple().
%% @private
prod_price_type(erlang_term, Price) ->
	{_, ProdPriceTypeS} = lists:keyfind("priceType", 1, Price),
	price_type(ProdPriceTypeS);
prod_price_type(json, Price) ->
	PPT = price_type(Price#price.type),
	{"priceType", PPT}.

-spec validity_period(StartTime, EndTime) -> Result
	when
		StartTime	:: string(),
		EndTime		:: string(),
		Result		:: pos_integer() | {error, Reason},
		Reason		:: term().
%% @doc return validity period of a product in milliseconds.
%% @private
validity_period(ISOSTime, ISOETime) when is_list(ISOSTime),
		is_list(ISOETime) ->
	case {ocs_rest:timestamp(ISOSTime), ocs_rest:timestamp(ISOETime)} of
		{{error, _}, _} ->
			{error, format_error};
		{_, {error, _}} ->
			{error, format_error};
		{STime, ETime} ->
			ETime - STime
	end.

-spec product_unit_of_measure(UnitsOfMeasure) -> Result
	when
		UnitsOfMeasure	:: string(),
		Result			:: {Units, Size},
		Units				:: undefined | unit_of_measure(),
		Size				:: undefined | pos_integer().
%% @doc return units type and size of measurement of a product
%% @private
product_unit_of_measure("") ->
	{undefined, undefined};
product_unit_of_measure(UnitsOfMeasure) ->
	LowerUOM = string:to_lower(UnitsOfMeasure),
	product_unit_of_measure1(LowerUOM).
%% @hidden
product_unit_of_measure1(UnitsOfMeasure) ->
	Suffix = "octets",
	case lists:suffix(Suffix, UnitsOfMeasure) of
		true ->
			[Size] = string:tokens(UnitsOfMeasure, Suffix),
			{octets, list_to_integer(Size)};
		false ->
			product_unit_of_measure2(UnitsOfMeasure)
	end.
%% @hidden
product_unit_of_measure2(UnitsOfMeasure) ->
	Suffix = "gb",
	case lists:suffix(Suffix, UnitsOfMeasure) of
		true ->
			[Size] = string:tokens(UnitsOfMeasure, Suffix),
			{gb, list_to_integer(Size)};
		false ->
			product_unit_of_measure3(UnitsOfMeasure)
	end.
%% @hidden
product_unit_of_measure3(UnitsOfMeasure) ->
	Suffix = "mb",
	case lists:suffix(Suffix, UnitsOfMeasure) of
		true ->
			[Size] = string:tokens(UnitsOfMeasure, Suffix),
			{mb, list_to_integer(Size)};
		false ->
			product_unit_of_measure4(UnitsOfMeasure)
	end.
%% @hidden
product_unit_of_measure4(UnitsOfMeasure) ->
	Suffix = "cents",
	case lists:suffix(Suffix, UnitsOfMeasure) of
		true ->
			[Size] = string:tokens(UnitsOfMeasure, Suffix),
			{cents, list_to_integer(Size)};
		false ->
			product_unit_of_measure5(UnitsOfMeasure)
	end.
%% @hidden
product_unit_of_measure5(UnitsOfMeasure) ->
	Suffix = "seconds",
	case lists:suffix(Suffix, UnitsOfMeasure) of
		true ->
			[Size] = string:tokens(UnitsOfMeasure, Suffix),
			{seconds, list_to_integer(Size)};
		false ->
			product_unit_of_measure6(UnitsOfMeasure)
	end.
%% @hidden
product_unit_of_measure6(_UnitsOfMeasure) ->
	{undefined, undefined}.

-spec product_size(UnitsFrom, UnitsTo, Size) -> Result
	when
		UnitsFrom	:: undefined | atom(), % gb | mb | second | cents
		UnitsTo		:: octets,
		Size			:: undefined | pos_integer(),
		Result		:: integer().
%% @private
product_size(UnitsFrom, octets, Size) when
		UnitsFrom == undefined; Size == undefined ->
	0;
product_size(gb, octets, Size) -> Size * 1000000000;
product_size(mb, octets, Size) -> Size * 1000000;
product_size(_, _, Size) -> Size.

-spec recurring_charge_period(RCPeriod) -> Result
	when
		RCPeriod	:: string(),
		Result	:: valid_period().
%% @doc return valid period
%% @private
recurring_charge_period("") -> undefined;
recurring_charge_period("yearly") -> yearly;
recurring_charge_period("monthly") -> monthly;
recurring_charge_period("weekly") -> weekly;
recurring_charge_period("daily") -> daily.

-spec find_status(StringStatus) -> Status when
	StringStatus	:: string(),
	Status			:: product_status().
%% @doc return life cycle status of the product
%% @private
find_status("active") -> active;
find_status("created") -> created;
find_status("aborted") -> aborted;
find_status("cancelled") -> cancelled;
find_status("suspended") -> suspended;
find_status("terminate") -> terminate;
find_status("pending_active") -> pending_active;
find_status("pending_terminate") -> pending_terminate.

-spec price_type(StringPriceType) -> PriceType when
	StringPriceType :: string() | atom(),
	PriceType		 :: recurring | one_time | usage | string().
%% @private
price_type("usage") -> usage;
price_type("recurring") -> recurring;
price_type("one_time") -> one_time;
price_type(usage) -> "usage";
price_type(recurring) -> "recurring";
price_type(one_time) -> "one_time".

