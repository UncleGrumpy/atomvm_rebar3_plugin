%%
%% Copyright (c) 2023 <fred@dushin.net>
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
-module(packbeam_tests).

-export([run/1]).

run(Opts) ->
    ok = test_defaults(Opts),
    ok = test_start(Opts),
    ok = test_prune(Opts),
    ok = test_rebar_overrides(Opts),
    ok = test_otp_application(Opts),
    ok.

%% @private
test_defaults(Opts) ->

    AppsDir = maps:get(apps_dir, Opts),
    AppDir = test:make_path([AppsDir, "myapp"]),

    Cmd = create_packbeam_cmd(AppDir, ["-f"], []), %% -f temporary during dev
    Output = test:execute_cmd(Cmd, Opts),
    test:debug(Output, Opts),

    ok = test:expect_contains("AVM file written to", Output),
    ok = test:expect_contains("_build/default/lib/myapp.avm", Output),
    AVMPath = test:make_path([AppDir, "_build/default/lib/myapp.avm"]),
    ok = test:file_exists(AVMPath),
    AVMElements = test:get_avm_elements(AVMPath),

    2 = length(AVMElements),
    [MyAppBeam, MyAppApplicationBin] = AVMElements,

    true = packbeam_api:is_beam(MyAppBeam),
    true = packbeam_api:is_entrypoint(MyAppBeam),

    false = packbeam_api:is_beam(MyAppApplicationBin),
    false = packbeam_api:is_entrypoint(MyAppApplicationBin),

    test:tick().

%% @private
test_start(Opts) ->

    AppsDir = maps:get(apps_dir, Opts),
    AppDir = test:make_path([AppsDir, "multi-start"]),

    Cmd = create_packbeam_cmd(AppDir, ["-f"], []), %% -f temporary during dev
    Output = test:execute_cmd(Cmd, Opts),
    test:debug(Output, Opts),

    ok = test:expect_contains("AVM file written to", Output),
    ok = test:expect_contains("_build/default/lib/myapp.avm", Output),
    AVMPath = test:make_path([AppDir, "_build/default/lib/myapp.avm"]),
    ok = test:file_exists(AVMPath),
    AVMElements = test:get_avm_elements(AVMPath),

    3 = length(AVMElements),
    [MyAppBeam, StartBeam, MyAppApplicationBin] = AVMElements,

    true = packbeam_api:is_beam(MyAppBeam),
    true = packbeam_api:is_entrypoint(MyAppBeam),

    true = packbeam_api:is_beam(StartBeam),
    true = packbeam_api:is_entrypoint(StartBeam),

    false = packbeam_api:is_beam(MyAppApplicationBin),
    false = packbeam_api:is_entrypoint(MyAppApplicationBin),

    %%
    %% Now specify `-s start` to get the start module first
    %%

    Cmd2 = create_packbeam_cmd(AppDir, ["-f", {"-s", "start"}], []),
    _Output2 = test:execute_cmd(Cmd2, Opts),
    AVMElements2 = test:get_avm_elements(AVMPath),

    3 = length(AVMElements2),
    [StartBeam, MyAppBeam, MyAppApplicationBin] = AVMElements2,

    test:tick().

%% @private
test_prune(Opts) ->

    AppsDir = maps:get(apps_dir, Opts),
    AppDir = test:make_path([AppsDir, "prune"]),

    Cmd = create_packbeam_cmd(AppDir, ["-f"], []), %% -f temporary during dev
    Output = test:execute_cmd(Cmd, Opts),
    test:debug(Output, Opts),

    ok = test:expect_contains("AVM file written to", Output),
    ok = test:expect_contains("_build/default/lib/myapp.avm", Output),
    AVMPath = test:make_path([AppDir, "_build/default/lib/myapp.avm"]),
    ok = test:file_exists(AVMPath),
    AVMElements = test:get_avm_elements(AVMPath),

    6 = length(AVMElements),

    {value, ABeam} = test:find_avm_element_by_name("a.beam", AVMElements),
    {value, BBeam} = test:find_avm_element_by_name("b.beam", AVMElements),
    {value, CBeam} = test:find_avm_element_by_name("c.beam", AVMElements),
    {value, DBeam} = test:find_avm_element_by_name("d.beam", AVMElements),

    true = packbeam_api:is_beam(ABeam),
    true = packbeam_api:is_beam(BBeam),
    true = packbeam_api:is_beam(CBeam),
    true = packbeam_api:is_beam(DBeam),

    %%
    %% Now specify `-p` to prune out d.beam, since no one references him
    %%

    Cmd2 = create_packbeam_cmd(AppDir, ["-f", "-p"], []),
    _Output2 = test:execute_cmd(Cmd2, Opts),
    AVMElements2 = test:get_avm_elements(AVMPath),

    5 = length(AVMElements2),
    {value, ABeam} = test:find_avm_element_by_name("a.beam", AVMElements2),
    {value, BBeam} = test:find_avm_element_by_name("b.beam", AVMElements2),
    {value, CBeam} = test:find_avm_element_by_name("c.beam", AVMElements2),
    false = test:find_avm_element_by_name("d.beam", AVMElements2),

    test:tick().

%% @private
test_rebar_overrides(Opts) ->

    AppsDir = maps:get(apps_dir, Opts),
    AppDir = test:make_path([AppsDir, "rebar_overrides"]),

    Cmd = create_packbeam_cmd(AppDir, ["-f"], []), %% -f temporary during dev
    Output = test:execute_cmd(Cmd, Opts),
    test:debug(Output, Opts),

    ok = test:expect_contains("AVM file written to", Output),
    ok = test:expect_contains("_build/default/lib/myapp.avm", Output),
    AVMPath = test:make_path([AppDir, "_build/default/lib/myapp.avm"]),
    ok = test:file_exists(AVMPath),
    AVMElements = test:get_avm_elements(AVMPath),

    3 = length(AVMElements),
    [StartBeam, MyAppBeam, MyAppApplicationBin] = AVMElements,

    true = packbeam_api:is_beam(MyAppBeam),
    true = packbeam_api:is_entrypoint(MyAppBeam),

    true = packbeam_api:is_beam(StartBeam),
    true = packbeam_api:is_entrypoint(StartBeam),

    false = packbeam_api:is_beam(MyAppApplicationBin),
    false = packbeam_api:is_entrypoint(MyAppApplicationBin),

    %%
    %% Now specify `-s myapp` to get the myapp module first
    %%

    Cmd2 = create_packbeam_cmd(AppDir, ["-f", {"-s", "myapp"}], []),
    _Output2 = test:execute_cmd(Cmd2, Opts),
    AVMElements2 = test:get_avm_elements(AVMPath),

    3 = length(AVMElements2),
    [MyAppBeam, StartBeam, MyAppApplicationBin] = AVMElements2,

    test:tick().

%% @private
test_otp_application(Opts) ->

    AppsDir = maps:get(apps_dir, Opts),
    AppDir = test:make_path([AppsDir, "otp_application"]),

    Cmd = create_packbeam_cmd(AppDir, ["-f"], []), %% -f temporary during dev
    Output = test:execute_cmd(Cmd, Opts),
    test:debug(Output, Opts),

    ok = test:expect_contains("AVM file written to", Output),
    ok = test:expect_contains("_build/default/lib/my_app.avm", Output),
    AVMPath = test:make_path([AppDir, "_build/default/lib/my_app.avm"]),
    ok = test:file_exists(AVMPath),
    AVMElements = test:get_avm_elements(AVMPath),

    [InitShimBeam | _Rest] = AVMElements,
    true = packbeam_api:is_beam(InitShimBeam),
    true = packbeam_api:is_entrypoint(InitShimBeam),

    {value, StartBoot} = test:find_avm_element_by_name("init/priv/start.boot", AVMElements),
    false = packbeam_api:is_beam(StartBoot),

    {value, MyAppBeam} = test:find_avm_element_by_name("my_app.beam", AVMElements),
    true = packbeam_api:is_beam(MyAppBeam),
    false = packbeam_api:is_entrypoint(MyAppBeam),

    {value, MyAppApplicationBin} = test:find_avm_element_by_name("my_app/priv/application.bin", AVMElements),
    false = packbeam_api:is_beam(MyAppApplicationBin),
    false = packbeam_api:is_entrypoint(MyAppApplicationBin),

    test:tick().

%% @private
create_packbeam_cmd(AppDir, Opts, Env) ->
    test:create_rebar3_cmd(AppDir, packbeam, Opts, Env).
