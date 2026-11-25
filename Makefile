FPC      := /usr/bin/fpc
FPCFLAGS := -O2 -XX -Mobjfpc -Sh -Fusrc -FEbuild -o./build/plamen
SRC      := src/plamen.dpr

all: build/plamen

build/plamen: $(wildcard src/*.pas src/*.dpr) tools/build.sh
	@bash tools/build.sh
	@mkdir -p build
	$(FPC) $(FPCFLAGS) $(SRC)

run: all
	./build/plamen

selftest: all
	./build/plamen selftest; echo "selftest RC=$$?"

clean:
	rm -rf build src/version.inc selftest.log error.log

.PHONY: all run selftest clean
