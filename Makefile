# sml-parsec build
#
#   make            build the test binary with MLton (default)
#   make test       build + run tests under MLton
#   make test-poly  run tests under Poly/ML (use-and-run; no link step)
#   make all-tests  run the suite under both compilers
#   make clean      remove build artifacts

MLTON      ?= mlton
POLY       ?= poly
BIN        := bin
LIBDIR     := lib/github.com/sjqtentacles/sml-parsec
TEST_MLB   := test/test.mlb
SRCS       := $(wildcard $(LIBDIR)/*.sml $(LIBDIR)/*.sig $(LIBDIR)/*.mlb) test/test.sml $(TEST_MLB)

.PHONY: all test poly test-poly all-tests clean

all: $(BIN)/test-mlton

$(BIN)/test-mlton: $(SRCS) | $(BIN)
	$(MLTON) -output $@ $(TEST_MLB)

test: $(BIN)/test-mlton
	$(BIN)/test-mlton

# Poly/ML has no native .mlb support; the test suite runs at top level and
# exits on its own, so we just `use` the sources in order. No executable is
# exported, which sidesteps any linker quirks.
poly test-poly:
	printf 'use "$(LIBDIR)/stream.sig";\nuse "$(LIBDIR)/parsec.sig";\nuse "$(LIBDIR)/parsecfn.sml";\nuse "$(LIBDIR)/charstream.sml";\nuse "$(LIBDIR)/charparseccore.sml";\nuse "$(LIBDIR)/charparsec.sig";\nuse "$(LIBDIR)/charparsec.sml";\nuse "$(LIBDIR)/expr.sig";\nuse "$(LIBDIR)/exprfn.sml";\nuse "$(LIBDIR)/charexpr.sml";\nuse "$(LIBDIR)/tokenstream.sml";\nuse "test/test.sml";\n' | $(POLY) -q --error-exit

all-tests: test test-poly

$(BIN):
	mkdir -p $(BIN)

clean:
	rm -rf $(BIN)
