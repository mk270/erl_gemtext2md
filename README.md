# gemtext2md

Convert Gemini text (gemtext) to Markdown. This is an Erlang library
plus a command line filter built from it. The conversion follows the
Rust `gemtext2md`, and parsing is done by
[gemini_text](https://hex.pm/packages/gemini_text).

## Conversion rules

| Gemtext                    | Markdown                        |
|----------------------------|---------------------------------|
| `# `, `## `, `### `        | same heading level              |
| text line                  | paragraph                       |
| `=> URL label`             | `* [label](URL)`                |
| `=> URL` (no label)        | `* [URL](URL)`                  |
| `* item`                   | `- item`                        |
| `> text`                   | `> text`                        |
| fenced block (with alt)    | fenced block, alt text kept     |

Consecutive links, list items or quote lines form one block. A blank
line or any other kind of line ends the block. Lines of a quote block
are separated by a bare `>` line, so each stays its own paragraph.
Blank lines are not otherwise reproduced; each block is followed by
one blank line.

Input must be UTF-8. Anything else is an error; transcode it first.
Control characters are passed through unfiltered.

## Library

Add the dependency to `rebar.config`:

```erlang
{deps, [{gemtext2md, "~> 0.1"}]}.
```

Whole document:

```erlang
{ok, Markdown} = gemtext2md:convert(<<"# Hello\n=> gemini://x.org X\n">>),
io:put_chars(Markdown).
```

`convert/1` returns `{ok, iodata()}` or `{error, Reason}`. The
reason comes from gemini_text, for example `invalid_utf8`.

Streaming, for input that arrives in pieces (chunks may be split
anywhere, including inside a line or a multibyte character):

```erlang
C0 = gemtext2md:new(),
{ok, Out1, C1} = gemtext2md:convert(Chunk1, C0),
{ok, Out2, C2} = gemtext2md:convert(Chunk2, C1),
{ok, Out3} = gemtext2md:finish(C2).
```

Write `Out1`, `Out2` and `Out3` in order. After an error no context
is returned, so a broken stream cannot be continued. Output for a
link, list or quote group is held back until the group ends (the next
element of another kind, or `finish/1`); a preformatted block is
held back until its closing fence.

## Escript

```
gemtext2md [FILE | -]
```

With no argument, or with `-`, it reads standard input; with one
argument it reads that file. Markdown goes to standard output.

```
$ gemtext2md page.gmi > page.md
$ curl -s gemini-proxy/page.gmi | gemtext2md
```

On failure it prints `gemtext2md: <message>` to standard error and
exits with status 1; otherwise it exits 0. It needs `escript` (an
Erlang/OTP install, 27 or later) on the PATH.

### Building

```
make release
```

This runs `rebar3 escriptize` and prints the sha256 of
`_build/default/bin/gemtext2md`.

### Using a released escript in another project's build

Pin the version and checksum, fetch once, and run it:

```make
GEMTEXT2MD_VSN = 0.1.0
GEMTEXT2MD_URL = https://example.org/gemtext2md/v$(GEMTEXT2MD_VSN)/gemtext2md
GEMTEXT2MD     = _build/tools/gemtext2md-$(GEMTEXT2MD_VSN)

$(GEMTEXT2MD):
	mkdir -p $(dir $@)
	curl -fsSL -o $@ $(GEMTEXT2MD_URL)
	echo "<sha256>  $@" | sha256sum -c -
	chmod +x $@

docs/%.md: docs/%.gmi $(GEMTEXT2MD)
	$(GEMTEXT2MD) $< > $@
```

Without an escript, the same code can be run from the library:
`gemtext2md_cli:main(Args)` is the escript entry point, and
`gemtext2md_cli:run(Args, OutDevice)` returns the exit status instead
of halting.

## Development

```
rebar3 eunit
rebar3 dialyzer
```

## Licence

Apache 2.0.
