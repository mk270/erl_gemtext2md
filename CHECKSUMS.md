# Release checksums

The escript's sha256 is what other projects pin when they download it
(see "Using a released escript in another project's build" in the
README). This note says where the number comes from and what to watch
out for.

## How it is produced

`make release` runs `rebar3 escriptize` and then
`sha256sum _build/default/bin/gemtext2md`. To checksum a file you
already have, run `sha256sum` on that file.

## Builds are not reproducible

Rebuilding the same source gives a different checksum. Observed on
2026-11-19: two consecutive `rebar3 escriptize` runs with no source
changes produced different hashes (`9d8fac11...` then `3e1fc690...`).
A further rebuild after touching a source file gave the second hash
again. The exact cause has not been investigated; the escript is a zip
archive, so embedded file metadata such as timestamps is a likely
candidate, but that is a guess.

So a checksum belongs to one particular file, not to a version of the
source.

## Release procedure

1. Run `make release` once and keep that file.
2. Attach exactly that file to the GitHub release for the version tag
   (for example `v0.1.0`), named `gemtext2md`.
3. Download the release asset again and run `sha256sum` on the download.
   This is the number to publish.
4. Put that number in the README example and tell consumers to use it in
   their Makefiles.

Do not rebuild between steps 1 and 3 and expect the same hash. After
publishing, do not replace the asset: consumers pin the hash, so a
changed file breaks their builds. If the escript needs to change, make
a new version and a new release.

## Reproducible builds

Not attempted. If wanted, first find out what the escript archive
embeds (build with the same source twice and compare the contents of
the two files), then see whether rebar3 or a post-processing step can
fix those values.
