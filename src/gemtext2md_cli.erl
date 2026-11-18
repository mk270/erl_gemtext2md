%% gemtext2md_cli: command line front end, also the escript entry point.
%%
%% Usage: gemtext2md [FILE | -]   (no argument or "-" reads stdin)

-module(gemtext2md_cli).

-export([main/1, run/2]).

-define(CHUNK, 65536).

-spec main([string()]) -> no_return().
main(Args) ->
    ok = io:setopts(standard_io, [binary, {encoding, latin1}]),
    halt(run(Args, standard_io)).

%% Returns the exit status; output goes to Out.
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
