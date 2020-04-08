%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2020 Marc Worrell
%% @doc Simple data storage in processes.

%% Copyright 2020 Marc Worrell
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(z_server_storage).

-behaviour(gen_server).

-export([
    ping/2,
    stop/2,
    lookup/3,
    store/4,
    delete/3
    ]).

-export([
    start_link/2,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    code_change/3,
    terminate/2
    ]).

-include_lib("zotonic_core/include/zotonic.hrl").

-define(SESSION_EXPIRE_N, 3600).

-record(state, {
        id :: binary(),
        timeout :: integer(),
        data :: map()
    }).

-spec start_link( binary(), z:context()) -> {ok, pid()} | {error, {already_started, pid()}}.
start_link(SessionId, Context) ->
    gen_server:start_link({via, z_proc, {{?MODULE, SessionId}, Context}}, ?MODULE, [SessionId, timeout(Context)], []).


%%% ------------------------------------------------------------------------------------
%%% API
%%% ------------------------------------------------------------------------------------


-spec lookup( binary(), term(), z:context() ) -> {ok, term()} | {error, not_found | no_session}.
lookup(SessionId, Key, Context) ->
    case z_proc:whereis({?MODULE, SessionId}, Context) of
        undefined -> {error, no_session};
        Pid -> gen_server:call(Pid, {lookup, Key})
    end.

-spec store( binary(), term(), term(), z:context() ) -> ok | {error, no_session}.
store(SessionId, Key, Value, Context) ->
    case z_proc:whereis({?MODULE, SessionId}, Context) of
        undefined -> {error, no_session};
        Pid -> gen_server:cast(Pid, {store, Key, Value})
    end.

-spec delete( binary(), term(), z:context() ) -> ok | {error, no_session}.
delete(SessionId, Key, Context) ->
    case z_proc:whereis({?MODULE, SessionId}, Context) of
        undefined -> {error, no_session};
        Pid -> gen_server:cast(Pid, {delete, Key})
    end.

-spec ping( binary(), z:context() ) -> ok | {error, no_session}.
ping(SessionId, Context) ->
    case z_proc:whereis({?MODULE, SessionId}, Context) of
        undefined -> {error, no_session};
        Pid -> gen_server:cast(Pid, ping)
    end.

-spec stop( binary(), z:context() ) -> ok | {error, no_session}.
stop(SessionId, Context) ->
    case z_proc:whereis({?MODULE, SessionId}, Context) of
        undefined -> {error, no_session};
        Pid -> gen_server:cast(Pid, stop)
    end.


%%% ------------------------------------------------------------------------------------
%%% gen_server callbacks
%%% ------------------------------------------------------------------------------------

init([SessionId, Timeout]) ->
    {ok, #state{
        id = SessionId,
        timeout = Timeout * 1000,
        data = #{}
    }, Timeout}.

handle_call({lookup, Key}, _From, #state{ data = Data } = State) ->
    case maps:find(Key, Data) of
        {ok, Value} ->
            {reply, {ok, Value}, State, State#state.timeout};
        error ->
            {reply, {error, not_found}, State, State#state.timeout}
    end.

handle_cast({store, Key, Value}, #state{ data = Data } = State) ->
    State1 = State#state{ data = Data#{ Key => Value } },
    {noreply, State1, State#state.timeout};
handle_cast({delete, Key}, #state{ data = Data } = State) ->
    State1 = State#state{ data = maps:remove(Key, Data) },
    {noreply, State1, State#state.timeout};
handle_cast(ping, State) ->
    {noreply, State, State#state.timeout};
handle_cast(stop, State) ->
    {stop, normal, State}.

handle_info(timeout, State) ->
    {stop, normal, State}.

code_change(_OldVersion, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.


%%% ------------------------------------------------------------------------------------
%%% support
%%% ------------------------------------------------------------------------------------

timeout(Context) ->
    z_convert:to_integer(m_config:get_value(site, session_expire_n, ?SESSION_EXPIRE_N, Context)).
