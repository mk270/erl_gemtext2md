-module(gemtext2md_cli_tests).
-include_lib("eunit/include/eunit.hrl").

tmp(Name) ->
    filename:join(filename:basedir(user_cache, "gemtext2md_test"), Name).

run_file(Contents) ->
    In = tmp("in.gmi"),
    OutF = tmp("out.md"),
    ok = filelib:ensure_dir(In),
    ok = file:write_file(In, Contents),
    {ok, Out} = file:open(OutF, [write, binary]),
    Status = gemtext2md_cli:run([In], Out),
    ok = file:close(Out),
    {ok, Data} = file:read_file(OutF),
    {Status, Data}.

file_test() ->
    ?assertEqual({0, <<"# T\n\nx\n\n">>}, run_file(<<"# T\nx\n">>)).

utf8_test() ->
    ?assertEqual({0, <<"caf",195,169,"\n\n">>},
                 run_file(<<"caf",195,169,"\n">>)).

bad_input_test() ->
    {Status, _} = run_file(<<255, $\n>>),
    ?assertEqual(1, Status).

missing_file_test() ->
    ?assertEqual(1, gemtext2md_cli:run(["/nonexistent/x.gmi"],
                                       standard_io)).

usage_test() ->
    ?assertEqual(1, gemtext2md_cli:run(["a", "b"], standard_io)).
