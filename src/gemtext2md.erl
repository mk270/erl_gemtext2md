%% gemtext2md: convert Gemini text to Markdown.
%%
%% The conversion follows the Rust gemtext2md: consecutive links, list
%% items and quote lines are grouped into one block each.  The
%% streaming API (new/0, convert/2, finish/1) sits on gemini_text's
%% streaming parser.  A group is written out when an element that does
%% not belong to it arrives, or at finish/1.

-module(gemtext2md).

-export([convert/1, new/0, convert/2, finish/1, render/1]).
-export_type([context/0]).

-opaque context() :: {gemini_text:context(), group()}.

-type group() :: none
               | {links, [{binary(), binary()}]}
               | {list, [binary()]}
               | {quote, [binary()]}.

%% Convert a whole document.
-spec convert(Text) -> Result
    when Text   :: binary(),
         Result :: {ok, iodata()} | {error, gemini_text:parse_error()}.
convert(Text) ->
    case gemini_text:parse(Text) of
        {ok, Elements} -> {ok, render(Elements)};
        {error, _} = E -> E
    end.

-spec new() -> context().
new() ->
    {gemini_text:new_context(), none}.

%% Feed a chunk; output is returned as soon as it is available.
-spec convert(Chunk, Ctx) -> Result
    when Chunk  :: binary(),
         Ctx    :: context(),
         Result :: {ok, iodata(), context()}
                 | {error, gemini_text:parse_error()}.
convert(Chunk, {PCtx, Group}) ->
    case gemini_text:parse(Chunk, PCtx) of
        {ok, Elements, PCtx1} ->
            {Out, Group1} = render(Elements, Group, []),
            {ok, Out, {PCtx1, Group1}};
        {error, _} = E ->
            E
    end.

-spec finish(Ctx) -> Result
    when Ctx    :: context(),
         Result :: {ok, iodata()} | {error, gemini_text:parse_error()}.
finish({PCtx, Group}) ->
    case gemini_text:finish(PCtx) of
        {ok, Elements} ->
            {Out, Group1} = render(Elements, Group, []),
            {ok, [Out, flush(Group1)]};
        {error, _} = E ->
            E
    end.

%% Render a whole list of parsed elements as Markdown.
-spec render(Elements) -> iodata()
    when Elements :: [gemini_text:tagged_line()].
render(Elements) ->
    {Out, Group} = render(Elements, none, []),
    [Out, flush(Group)].

%% Returns the output so far and the group still open.
-spec render([gemini_text:tagged_line()], group(), iodata()) ->
          {iodata(), group()}.
render([], G, Acc) ->
    {lists:reverse(Acc), G};
render([{link, Url, Label} | T], {links, Ls}, Acc) ->
    render(T, {links, [{Url, Label} | Ls]}, Acc);
render([{list_item, X} | T], {list, Is}, Acc) ->
    render(T, {list, [X | Is]}, Acc);
render([{quote, X} | T], {quote, Qs}, Acc) ->
    render(T, {quote, [X | Qs]}, Acc);
render([E | T], G, Acc) ->
    Acc1 = [flush(G) | Acc],
    case E of
        {link, Url, Label} -> render(T, {links, [{Url, Label}]}, Acc1);
        {list_item, X}     -> render(T, {list, [X]}, Acc1);
        {quote, X}         -> render(T, {quote, [X]}, Acc1);
        blank              -> render(T, none, Acc1);
        _                  -> render(T, none, [block(E) | Acc1])
    end.

-spec flush(group()) -> iodata().
flush(none) ->
    [];
flush({links, Ls}) ->
    [[<<"* [">>, caption(Url, Label), <<"](">>, Url, <<")\n">>]
     || {Url, Label} <- lists:reverse(Ls)] ++ [<<"\n">>];
flush({list, Is}) ->
    [[<<"- ">>, I, <<"\n">>] || I <- lists:reverse(Is)] ++ [<<"\n">>];
flush({quote, Qs}) ->
    Lines = [[<<"> ">>, Q, <<"\n">>] || Q <- lists:reverse(Qs)],
    lists:join(<<">\n">>, Lines) ++ [<<"\n">>].

caption(Url, <<>>) -> Url;
caption(_Url, Label) -> Label.

-spec block(gemini_text:tagged_line()) -> iodata().
block({h1, T})   -> [<<"# ">>, T, <<"\n\n">>];
block({h2, T})   -> [<<"## ">>, T, <<"\n\n">>];
block({h3, T})   -> [<<"### ">>, T, <<"\n\n">>];
block({para, T}) -> [T, <<"\n\n">>];
block({preformatted, Alt, Lines}) ->
    [<<"```">>, Alt, <<"\n">>,
     [[L, <<"\n">>] || L <- Lines],
     <<"```\n\n">>].
