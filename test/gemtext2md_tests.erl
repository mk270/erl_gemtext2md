-module(gemtext2md_tests).
-include_lib("eunit/include/eunit.hrl").

md(Elements) ->
    iolist_to_binary(gemtext2md:render(Elements)).

render_test_() ->
    [?_assertEqual(<<"# T\n\n## U\n\n### V\n\nhello\n\n">>,
                   md([{h1, <<"T">>}, {h2, <<"U">>}, {h3, <<"V">>},
                       {para, <<"hello">>}])),
     ?_assertEqual(<<"para\n\nnext\n\n">>,
                   md([{para, <<"para">>}, blank, {para, <<"next">>}])),
     ?_assertEqual(<<"```alt\na\n\n```\n\n">>,
                   md([{preformatted, <<"alt">>, [<<"a">>, <<>>]}])),
     ?_assertEqual(<<"```\n```\n\n">>,
                   md([{preformatted, <<>>, []}]))].

group_test_() ->
    [?_assertEqual(<<"* [A](u1)\n* [u2](u2)\n\n">>,
                   md([{link, <<"u1">>, <<"A">>},
                       {link, <<"u2">>, <<>>}])),
     ?_assertEqual(<<"* [A](u1)\n\nx\n\n* [B](u2)\n\n">>,
                   md([{link, <<"u1">>, <<"A">>}, {para, <<"x">>},
                       {link, <<"u2">>, <<"B">>}])),
     ?_assertEqual(<<"- a\n- b\n\n">>,
                   md([{list_item, <<"a">>}, {list_item, <<"b">>}])),
     ?_assertEqual(<<"> a\n>\n> b\n\n">>,
                   md([{quote, <<"a">>}, {quote, <<"b">>}])),
     %% a blank line ends a group
     ?_assertEqual(<<"- a\n\n- b\n\n">>,
                   md([{list_item, <<"a">>}, blank,
                       {list_item, <<"b">>}]))].

convert_test_() ->
    [?_assertEqual({ok, <<"# T\n\nx\n\n">>},
                   begin
                       {ok, D} = gemtext2md:convert(<<"# T\nx\n">>),
                       {ok, iolist_to_binary(D)}
                   end),
     ?_assertMatch({error, _}, gemtext2md:convert(<<255, $\n>>))].

streaming_test() ->
    Text = <<"# T\r\n=> u l\r\nx\n">>,
    {ok, Whole} = gemtext2md:convert(Text),
    Chunks = [<<C>> || <<C>> <= Text],
    {Out, Ctx} = lists:foldl(
                   fun(C, {Acc, Ctx0}) ->
                           {ok, D, Ctx1} = gemtext2md:convert(C, Ctx0),
                           {[Acc, D], Ctx1}
                   end, {[], gemtext2md:new()}, Chunks),
    {ok, Rest} = gemtext2md:finish(Ctx),
    ?assertEqual(iolist_to_binary(Whole), iolist_to_binary([Out, Rest])).

stream(Chunks) ->
    {Out, Ctx} = lists:foldl(
                   fun(C, {Acc, Ctx0}) ->
                           {ok, D, Ctx1} = gemtext2md:convert(C, Ctx0),
                           {[Acc, D], Ctx1}
                   end, {[], gemtext2md:new()}, Chunks),
    {ok, Rest} = gemtext2md:finish(Ctx),
    iolist_to_binary([Out, Rest]).

parsed_features_test_() ->
    Text = <<"# T\n* a\n* b\n> q1\n> q2\n=> u l\n=> v\n"
             "```x\n=> not a link\n```\ncaf", 195, 169, "\r\nend">>,
    {ok, Whole} = gemtext2md:convert(Text),
    Want = iolist_to_binary(Whole),
    [?_assertEqual(<<"# T\n\n- a\n- b\n\n> q1\n>\n> q2\n\n"
                     "* [l](u)\n* [v](v)\n\n"
                     "```x\n=> not a link\n```\n\n"
                     "caf", 195, 169, "\n\nend\n\n">>, Want)
     | [?_assertEqual(Want, stream([binary:part(Text, 0, N),
                                    binary:part(Text, N,
                                                byte_size(Text) - N)]))
        || N <- lists:seq(0, byte_size(Text))]].

output_before_finish_test() ->
    %% a paragraph is written at once, a list is held until it ends
    {ok, Out, C} = gemtext2md:convert(<<"# T\nx\n* a\n">>,
                                      gemtext2md:new()),
    ?assertEqual(<<"# T\n\nx\n\n">>, iolist_to_binary(Out)),
    {ok, Out2} = gemtext2md:finish(C),
    ?assertEqual(<<"- a\n\n">>, iolist_to_binary(Out2)).

stream_error_test() ->
    {ok, _, C} = gemtext2md:convert(<<"a\n">>, gemtext2md:new()),
    ?assertEqual({error, {invalid_utf8, 2}},
                 gemtext2md:convert(<<255, $\n>>, C)).
