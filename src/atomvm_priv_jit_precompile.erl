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
-module(atomvm_priv_jit_precompile).

-behaviour(provider).

-export([init/1, do/1, format_error/1]).

-define(PROVIDER, jit_precompile).
-define(NAMESPACE, atomvm).
-define(DEPS, [bootstrap, {default, app_discovery}]).
-define(OPTS, [
    {arch, $t, "arch", string, "Target architecture"}
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
        {example, "rebar3 atomvm compile --arch host"},
        % list of options understood by the plugin
        {opts, ?OPTS},
        {short_desc, "Compiles native code"},
        {desc,
            "~n"
            "This plugin is used to compile native code.~n"
            "~n"
            "Supported target architectures are currently x86_64 and aarch64,~n"
            "emu will skip generating native code."
            "~n"
            "Any atomvm_rebar3_plugin configuration options for the jit_precompile~n"
            "arch will take precedence over options for compile arch."}
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
                Target ->
                    do_jit_precompile(
                        Target,
                        rebar_state:project_apps(State)
                    )
            end,
        {ok, State}
    catch
        C:E:S ->
            rebar_api:error(
                "An error occurred in the ~p ~p task. Error: ~p~n", [
                    ?NAMESPACE, ?PROVIDER, E
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
    CompileOpts = atomvm_rebar3_plugin:get_atomvm_rebar_provider_config(State, compile),
    Opts = maps:merge(
        maps:merge(?DEFAULT_OPTS, CompileOpts),
        maps:merge(RebarOpts, ParsedOpts)
    ),
    maps:update(arch, atomvm_rebar3_plugin:validate_compile_target(maps:get(arch, Opts)), Opts).

%% @private
do_jit_precompile(Target, ProjectApps) ->
    lists:foreach(
        fun(ProjectApp) ->
            maybe_jit_precompile_app(Target, ProjectApp)
        end,
        ProjectApps
    ).

%% @private
maybe_jit_precompile_app(Target, App) ->
    SrcDir = filename:join(
        rebar_app_info:out_dir(App),
        "ebin"
    ),
    OutDir = filename:join(SrcDir, Target),
    maybe_jit_precompile_app(Target, OutDir, SrcDir).

maybe_jit_precompile_app(Target, OutDir, SrcDir) ->
    case filelib:is_dir(SrcDir) of
        true ->
            Beams = filelib:wildcard("*.beam", SrcDir),
            Bytecode = lists:foldl(
                fun(Src, List) ->
                    [filename:join(SrcDir, Src) | List]
                end,
                [],
                Beams
            ),
            Jits = filelib:wildcard("*.beam", OutDir),
            Nativecode = lists:foldl(
                fun(Src, List) ->
                    [filename:join(OutDir, Src) | List]
                end,
                [],
                Jits
            ),
            case needs_compile(Nativecode, Bytecode) of
                false ->
                    rebar_api:info("Jit precompiled beams already exist for ~s", [Target]);
                true ->
                    case filelib:ensure_path(OutDir) of
                        ok ->
                            ok;
                        {error, _} ->
                            rebar_api:debug("Creating output dir for native code beams: ~s", [
                                OutDir
                            ]),
                            file:make_dir(OutDir)
                    end,
                    rebar_api:info("Compiling native code for ~p", [Target]),
                    lists:foreach(
                        fun(Beam) -> maybe_jit_precompile_file(Target, OutDir, Beam) end, Bytecode
                    )
            end;
        _ ->
            rebar_api:abort("Source dir ~s is not a directory.", [SrcDir])
    end.

%% @private
maybe_jit_precompile_file(Target, Out, Beam) ->
    Native = filename:join(Out, filename:basename(Beam)),
    case file_needs_compile(Native, Beam) of
        true ->
            rebar_api:debug("Compiling ~s to ~s native code...", [Beam, Target]),
            do_jit_precompile_file(Target, Out, Beam);
        false ->
            ok
    end.

%% @private
do_jit_precompile_file(Target, Out, Beam) ->
    rebar_api:debug(
        "Executing jit_precompile with options:~n  --target ~p --out ~s, --source ~s",
        [Target, Out, Beam]
    ),
    jit_precompile:compile(Target, Out, Beam).

%% @private
-spec needs_compile(list(), list()) -> true | false.
needs_compile([], _Beam) ->
    true;
needs_compile(Native, Beam) ->
    rebar_api:debug("Checking if rebuild in needed, sources: ~p, output: ~p", [Beam, Native]),
    not all_files_are_compiled(Native, Beam) orelse
        atomvm_rebar3_plugin:latest_modified_time(Native) <
            atomvm_rebar3_plugin:latest_modified_time(Beam).

%% @private
-spec file_needs_compile(file:name_all(), file:name_all()) -> true | false.
file_needs_compile(Native, Beam) ->
    not filelib:is_file(Native) orelse
        atomvm_rebar3_plugin:modified_time(Native) < atomvm_rebar3_plugin:modified_time(Beam).

-spec all_files_are_compiled(list(), list()) -> true | false.
all_files_are_compiled(_Beams, []) ->
    true;
all_files_are_compiled(Beams, Sources) ->
    [Source | SrcFiles] = Sources,
    File = filename:basename(Source),
    [Beam | _Targets] = Beams,
    OutDir = filename:dirname(Beam),
    case filelib:is_file(filename:join([OutDir, File])) of
        true ->
            all_files_are_compiled(Beams, SrcFiles);
        false ->
            false
    end.
