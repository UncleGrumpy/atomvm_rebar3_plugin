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
-module(atomvm_priv_packedbeam_parser).

-export([get_target_arch/1]).

-spec get_target_arch(Path :: file:name_all()) -> Arch :: string().
get_target_arch(Path) ->
    {ok, AVMData} = file:read_file(Path),
    parse_avmn_arch(AVMData, 16#40).

parse_avmn_arch(<<Chunk:4/binary, AVMdata/binary>>, Offset) ->
    case Chunk of
        <<$a, $v, $m, $N>> ->
            <<_Something:64, _LabelsCount:32, _Format_Version:16, 1:16, Arch:16, _Variant:16, 0:32,
                _Code/binary>> = AVMdata,
            Target = atomvm_rebar3_plugin:validate_compile_target(Arch),
            rebar_api:debug("~s: found target arch ~s", [?MODULE, Target]),
            Target;
        _ ->
            parse_avmn_arch(AVMdata, Offset + 32)
    end;
parse_avmn_arch(<<>>, _Offset) ->
    rebar_api:debug("~s: no avmN sections found assuming \"emu\"", [?MODULE]),
    "emu".
