%%
%% Copyright (c) 2020-2023 Fred Dushin <fred@dushin.net>
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
%%
%% SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
%%
-module(atomvm_rebar3_plugin).

-include_lib("jit/include/jit.hrl").
-include_lib("kernel/include/file.hrl").

-export([init/1]).

%% internal API
-export([
    proplist_to_map/1,
    get_atomvm_rebar_provider_config/2,
    validate_compile_target/1,
    modified_time/1,
    latest_modified_time/1
]).

-define(PROVIDERS, [
    atomvm_bootstrap_provider,
    atomvm_compile_provider,
    atomvm_packbeam_provider,
    atomvm_dialyzer_provider,
    atomvm_esp32_flash_provider,
    atomvm_pico_flash_provider,
    atomvm_stm32_flash_provider,
    atomvm_uf2create_provider,
    atomvm_version_provider,
    legacy_packbeam_provider,
    legacy_esp32_flash_provider,
    legacy_stm32_flash_provider
]).

-type proplist() :: [{term(), term()} | term()].

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    lists:foldl(
        fun(Cmd, {ok, StateAcc}) ->
            apply(Cmd, init, [StateAcc])
        end,
        {ok, State},
        ?PROVIDERS
    ).

-spec proplist_to_map(Proplist :: proplist()) -> map().
proplist_to_map(Proplist) ->
    proplist_to_map(Proplist, #{}).

%% @private
proplist_to_map([], Accum) ->
    Accum;
proplist_to_map([{K, V} | T], Accum) ->
    proplist_to_map(T, Accum#{K => V});
proplist_to_map([K | T], Accum) ->
    proplist_to_map(T, Accum#{K => true}).

-spec get_atomvm_rebar_provider_config(State :: term(), Provider :: atom()) -> map().
get_atomvm_rebar_provider_config(State, Provider) ->
    case rebar_state:get(State, ?MODULE, undefined) of
        undefined ->
            #{};
        AtomVM ->
            proplist_to_map(proplists:get_value(Provider, AtomVM, []))
    end.

-spec modified_time(Path :: file:name_all()) -> file:date_time() | non_neg_integer().
modified_time(Path) ->
    {ok, #file_info{mtime = MTime}} = file:read_file_info(Path, [{time, posix}]),
    MTime.

-spec latest_modified_time(PathList :: file:name_all()) -> file:date_time() | non_neg_integer().
latest_modified_time(PathList) ->
    lists:max([modified_time(Path) || Path <- PathList]).

-spec validate_compile_target(Target :: string() | atom() | non_neg_integer()) -> string().
validate_compile_target(Target) ->
    case Target of
        ?JIT_ARCH_X86_64 ->
            "x86_64";
        "x86_64" ->
            "x86_64";
        x86_64 ->
            "x86_64";
        ?JIT_ARCH_AARCH64 ->
            "aarch64";
        "aarch64" ->
            "aarch64";
        aarch64 ->
            "aarch64";
        "arm64" ->
            "aarch64";
        arm64 ->
            "aarch64";
        ?JIT_ARCH_ARMV6M ->
            "armv6m";
        "armv6m" ->
            "armv6m";
        armv6m ->
            "armv6m";
        "arm32" ->
            "armv6m";
        arm32 ->
            "armv6m";
        "host" ->
            get_host_arch();
        host ->
            get_host_arch();
        "emu" ->
            "emu";
        emu ->
            "emu";
        Unsupported ->
            rebar_api:error("Cannot compile native code for unsupported ~s target", [Unsupported])
    end.

%% @private
get_host_arch() ->
    Arch = string:trim(os:cmd("uname -m")),
    validate_compile_target(Arch).
