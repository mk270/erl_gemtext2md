-module(gemtext2md).

-moduledoc """
Convert Gemini text (gemtext) to Markdown.

Parsing is done by `m:gemini_text`. The conversion follows the Rust
`gemtext2md`:

- headings keep their level, and text lines become paragraphs;
- a link becomes `* [label](URL)`, or `* [URL](URL)` without a label;
- a list item becomes `- item`;
- a quote line becomes `> text`, with a bare `>` line between the lines
  of a quote block, so each stays its own paragraph;
- a preformatted block becomes a fenced block, keeping its alt text.

Consecutive links, list items or quote lines form one block. A blank
line, or any other kind of line, ends it. Each block is followed by one
blank line.

The input must be UTF-8; transcode anything else first. Control
characters are passed through, so sanitise the result before display
if the source is untrusted.

There are two ways in. `convert/1` takes a whole document. `new/0`,
`convert/2` and `finish/1` take it in pieces, which may be split
anywhere:

```erlang
C0 = gemtext2md:new(),
{ok, Out1, C1} = gemtext2md:convert(Chunk1, C0),
{ok, Out2, C2} = gemtext2md:convert(Chunk2, C1),
{ok, Out3} = gemtext2md:finish(C2).
```

Write the outputs in order. A link, list or quote group is held back
until it ends, and a preformatted block until its closing fence, so
`finish/1` may return output too. After an error no context is
returned, so a broken stream cannot be continued.

Errors are those of `gemini_text:parse/1`: `{Reason, LineNumber}`, for
example `{invalid_utf8, 3}`.
""".

-export([convert/1, new/0, convert/2, finish/1, render/1]).
-export_type([context/0]).

-doc """
The state of a streaming conversion, made by `new/0`.
""".
-opaque context() :: {gemini_text:context(), group()}.

-type group() :: none
               | {links, [{binary(), binary()}]}
               | {list, [binary()]}
               | {quote, [binary()]}.

-doc """
Convert a whole document to Markdown.

Returns `{ok, Markdown}` or `{error, {Reason, LineNumber}}`, for
example `{error, {invalid_utf8, 3}}`.
""".
-spec convert(Text) -> Result
    when Text   :: binary(),
         Result :: {ok, iodata()} | {error, gemini_text:parse_error()}.
convert(Text) ->
    case gemini_text:parse(Text) of
        {ok, Elements} -> {ok, render(Elements)};
        {error, _} = E -> E
    end.

-doc """
Start a streaming conversion.
""".
-spec new() -> context().
new() ->
    {gemini_text:new_context(), none}.

-doc """
Feed a chunk of input, which may end anywhere in a line.

Returns the Markdown that is complete so far, and the new context. The
errors are those of `convert/1`; after one, no context is returned.
""".
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

-doc """
End the input, returning any Markdown still held back: an unterminated
last line, a group still open, or a preformatted block that was never
closed. The errors are those of `convert/1`.
""".
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

-doc """
Render elements already parsed by `gemini_text:parse/1` as Markdown.
""".
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
