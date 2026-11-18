# "make release" builds the escript and prints its sha256, for pasting
# into the release notes and consumers' Makefiles.

ESCRIPT = _build/default/bin/gemtext2md

.PHONY: release test
release:
	rebar3 escriptize
	sha256sum $(ESCRIPT)

test:
	rebar3 eunit
