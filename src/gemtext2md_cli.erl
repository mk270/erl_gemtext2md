-module(gemtext2md_cli).

-moduledoc """
The command line front end of `m:gemtext2md`, and the entry point of the
`gemtext2md` escript.

    gemtext2md [FILE | -]

With no argument, or with `-`, it reads standard input; with one
argument it reads that file. Markdown goes to standard output. On
failure it prints `gemtext2md: MESSAGE` to standard error and exits
with status 1.

Input is read in chunks and passed to the streaming API of
`m:gemtext2md`, as raw bytes, so that invalid UTF-8 is reported rather
than silently re-encoded.
""".

-export([main/1, run/2]).

-define(CHUNK, 65536).

-doc """
The escript entry point: runs on the command line arguments and halts
with the exit status of `run/2`.
""".
-spec main([string()]) -> no_return().
main(Args) ->
    ok = io:setopts(standard_io, [binary, {encoding, latin1}]),
    halt(run(Args, standard_io)).

-doc """
Run on a list of arguments (see the module description), writing the
Markdown to `Out`.

Returns the exit status, 0 or 1, instead of halting, so that it can be
used from other code.
""".
-spec run(Args, Out) -> non_neg_integer()
    when Args :: [string()],
         Out  :: io:device().
run([], Out)    -> run(["-"], Out);
run(["-"], Out) -> convert_device(standard_io, Out);
run([File], Out) ->
    case file:open(File, [read, binary, raw]) of
        {ok, Dev} ->
            try convert_device(Dev, Out) after file:close(Dev) end;
        {error, Reason} ->
            fail("~ts: ~ts", [File, file:format_error(Reason)])
    end;
run(_, _) ->
    fail("usage: gemtext2md [FILE | -]", []).

convert_device(In, Out) ->
    loop(In, Out, gemtext2md:new()).

loop(In, Out, Ctx) ->
    case read(In) of
        eof ->
            case gemtext2md:finish(Ctx) of
                {ok, Data}  -> write(Out, Data);
                {error, E}  -> fail_error(E)
            end;
        {ok, Chunk} ->
            case gemtext2md:convert(Chunk, Ctx) of
                {ok, Data, Ctx1} ->
                    0 = write(Out, Data),
                    loop(In, Out, Ctx1);
                {error, E} -> fail_error(E)
            end;
        {error, Reason} ->
            fail("read error: ~p", [Reason])
    end.

read(standard_io) ->
    %% latin1 requests give the raw bytes; io:get_chars/3 would
    %% re-encode them and hide invalid UTF-8 from gemini_text
    case io:request(standard_io, {get_chars, latin1, '', ?CHUNK}) of
        eof -> eof;
        {error, R} -> {error, R};
        Data -> {ok, iolist_to_binary(Data)}
    end;
read(Dev) ->
    case file:read(Dev, ?CHUNK) of
        {ok, Data} -> {ok, Data};
        Other -> Other
    end.

write(Out, Data) ->
    %% a closed stdout (EPIPE) is not an error worth reporting
    _ = catch io:request(Out, {put_chars, latin1,
                               iolist_to_binary(Data)}),
    0.

fail_error({Reason, Line}) ->
    fail("line ~w: ~p", [Line, Reason]).

fail(Fmt, Args) ->
    io:format(standard_error, "gemtext2md: " ++ Fmt ++ "~n", Args),
    1.
