%%% @author     Max Lapshin <max@maxidoors.ru> [http://erlyvideo.org]
%%% @copyright  2010-2012 Max Lapshin
%%% @doc        api handler
%%% @reference  See <a href="http://erlyvideo.org" target="_top">http://erlyvideo.org</a> for more information
%%% @end
%%%
%%%
%%% This file is part of erlyvideo.
%%% 
%%% erlmedia is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU General Public License as published by
%%% the Free Software Foundation, either version 3 of the License, or
%%% (at your option) any later version.
%%%
%%% erlmedia is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with erlmedia.  If not, see <http://www.gnu.org/licenses/>.
%%%
%%%---------------------------------------------------------------------------------------
-module(api_handler).
-author('Max Lapshin <max@maxidoors.ru>').
-include("log.hrl").

-behaviour(cowboy_http_handler).
-export([init/3, handle/2, terminate/2]).

-export([init/4, handle_event/2, stream/3, info/3]).


%% Cowboy API

init({_Any,http}, Req, Opts) ->
  Mode = proplists:get_value(mode, Opts),
  {ok, Req, {Mode,Opts}}.

handle(Req, {reload, Opts}) ->
  check_auth(Req, Opts, admin, fun() -> 
    {ok, R1} = cowboy_http_req:reply(200, [{'Content-Type', <<"application/json">>}], "true\n", Req),
    spawn(fun() -> flu:reconf() end),
    {ok, R1, undefined}
  end);
  

handle(Req, {streams, Opts}) ->
  check_auth(Req, Opts, viewer, fun() ->
    {ok, R1} = cowboy_http_req:reply(200, [{'Content-Type', <<"application/json">>}], [mochijson2:encode(flu_stream:json_list()), "\n"], Req),
    {ok, R1, undefined}
  end);

handle(Req, {health, Opts}) ->
  check_auth(Req, Opts, viewer, fun() ->
    {PathInfo, _} = cowboy_http_req:path_info(Req),
    Name = flu:join(PathInfo, "/"),
    StreamInfo = proplists:get_value(Name, flu_stream:list(), []),
    Delay = proplists:get_value(ts_delay, StreamInfo),
    Limit = 5000,
    {ok, R1} = if
      is_number(Delay) andalso Delay < Limit ->
        cowboy_http_req:reply(200, [{<<"Content-Type">>, <<"application/json">>}], <<"true\n">>, Req);
      true ->
        cowboy_http_req:reply(412, [{<<"Content-Type">>, <<"application/json">>}], <<"false\n">>, Req)
    end,
    {ok, R1, undefined}
  end).

terminate(_,_) -> ok.

check_auth(Req, Opts, Class, Fun) ->
  check_auth(Req, Opts, Class, handle, Fun).
  

check_auth(Req, Opts, Class, Caller, Fun) ->
  case lists:keyfind(Class, 1, Opts) of
    {Class, Login, Password} ->
      check_password(Req, Login, Password, Caller, Fun);
    false ->
      case lists:keyfind(auth, 1, Opts) of
        {auth, Login, Password} -> check_password(Req, Login, Password, Caller, Fun);
        false -> Fun()
      end
  end.
      
check_password(Req, Login, Password, Caller, Fun) ->
  {Auth, Req1} = cowboy_http_req:header('Authorization', Req),
  GoodAuth = iolist_to_binary(["Basic ", base64:encode_to_string(Login++":"++Password)]),
  if Auth == GoodAuth -> Fun();
  true -> 
    {ok, Req2} = cowboy_http_req:reply(401, [], "401 Forbidden\n", Req1),
    case Caller of
      handle -> {ok, Req2, undefined};
      init -> {shutdown, Req2, undefined}
    end
  end.



%% Bullet API

init(_Transport, Req, _Options, _Kind) ->
  % ?D({init_comet,self()}),
  case erlang:whereis(flu_event) of
    undefined -> timer:sleep(1000);
    _ -> ok
  end,
  flu_event:add_sup_handler(?MODULE, [self()]),
  {ok, Req, state}.

handle_event(Event, Pid) ->
  Pid ! Event,
  {ok, Pid, hibernate}.

stream(<<"streams">>, Req, State) ->
  {reply, mochijson2:encode([{event, <<"stream.list">>}|flu_stream:json_list()]), Req, State};

stream(Data, Req, State) ->
  {Path, _Req2} = cowboy_http_req:raw_path(Req),
  ?D({stream, Path, Data}),
  {reply, Data, Req, State}.

info({tcp, _, _}, Req, State) ->
  {ok, Req, State};

info(Msg, Req, State) ->
  % {Path, Req2} = cowboy_http_req:raw_path(Req),
  % ?D({msg,Msg, flu_event:to_json(Msg)}),
  {reply, [flu_event:to_json(Msg), "\n"], Req, State}.

  
  

  



