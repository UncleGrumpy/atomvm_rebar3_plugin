%%
%% Copyright (c) 2025 Winford (UncleGrumpy) <winford@object.stream>
%% All rights reserved.
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
%%
%
% SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
%
-module(atomvm_compile_provider).

-behaviour(provider).

-export([init/1, do/1, format_error/1]).

-define(PROVIDER, compile).
-define(NAMESPACE, atomvm).
-define(DEPS, [bootstrap]).
-define(OPTS, [
    {arch, $t, "arch", string,
        "Target architecture if using the jit compiler (default emu, no jit)"}
]).

-define(DEFAULT_OPTS, #{
    arch => "emu"
}).

-include_lib("kernel/include/file.hrl").

%%
%% provider implementation
%%

%% @hidden
-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([
        % The atomvm namespace
        {namespace, ?NAMESPACE},
        % The 'user friendly' name of the task
        {name, ?PROVIDER},
        % The module implementation of the task
        {module, ?MODULE},
        % The task can be run by the user, always true
        {bare, true},
        % The list of dependencies
        {deps, ?DEPS},
        % How to use the plugin
        {example, "rebar3 atomvm compile"},
        % list of options understood by the plugin
        {opts, ?OPTS},
        {short_desc, "AtomMV compile options"},
        {desc,
            "~n"
            "This plugin is generally called internally by packbeam.~n"
            "~n"
            "The default compiler is the 'emu' bytecode compiler, but optionally the jit compiler may~n"
            "be used to precompile native code.~n"
            "~n"
            "Supported target architectures for the jit compiler are currently x86_64, aarch64~n"
            "and arm32 (or armv6m), If the target is 'host', then the native architecture of the host~n"
            "system will be used.~n"}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

%% @hidden
-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    try
        Opts = get_opts(State),
        rebar_api:debug("Effective opts for ~p: ~p", [?PROVIDER, Opts]),
        ok =
            case maps:get(arch, Opts) of
                "emu" ->
                    ok;
                _Arch ->
                    atomvm_priv_jit_precompile:do(State),
                    ok
            end,
        {ok, State}
    catch
        C:E:S ->
            rebar_api:error(
                "An error occurred in the ~p task. Error: ~p~n", [
                    ?PROVIDER, E
                ]
            ),
            rebar_api:debug(
                "Class=~p Error=~p~n=== Stacktrace ==>~n~p~n", [
                    C, E, S
                ]
            ),
            {error, E}
    end.

%% @hidden
-spec format_error(any()) -> iolist().
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

%%
%% internal functions
%%

%% @private
get_opts(State) ->
    {ParsedArgs, _} = rebar_state:command_parsed_args(State),
    RebarOpts = atomvm_rebar3_plugin:get_atomvm_rebar_provider_config(State, ?PROVIDER),
    ParsedOpts = atomvm_rebar3_plugin:proplist_to_map(ParsedArgs),
    Opts = maps:merge(
        ?DEFAULT_OPTS,
        maps:merge(RebarOpts, ParsedOpts)
    ),
    maps:update(arch, atomvm_rebar3_plugin:validate_compile_target(maps:get(arch, Opts)), Opts).
