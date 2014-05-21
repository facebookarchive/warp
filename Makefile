# Figure out which compiler to use (prefer gdc, fall back to dmd).
ifeq (,$(DC))
	DC:=$(shell which gdc 2>/dev/null)
ifeq (,$(DC))
	DC:=dmd
endif
endif

ifeq (gdc,$(notdir $(DC)))
	DFLAGS=-c -O4 -frelease -fno-bounds-check -fbuiltin
	OFSYNTAX=-o
else
ifeq (dmd,$(notdir $(DC)))
	DFLAGS=-c -O -inline -release
	OFSYNTAX=-of
else
    $(error Unsupported compiler: $(DC))
endif
endif

CC=cc
CXX=c++
CFLAGS=
CXXFLAGS=
WARPDRIVE=warpdrive
GENERATED_DEFINES=generated_defines.d

# warp sources
SRCS=cmdline.d constexpr.d context.d directive.d expanded.d file.d \
id.d lexer.d loc.d macros.d main.d number.d outdeps.d ranges.d skip.d \
sources.d stringlit.d textbuf.d charclass.d

# Binaries generated
BIN:=warp $(WARPDRIVE)

# Rules

all : $(BIN)

clean :
	rm -rf $(BIN) $(addsuffix .o, $(BIN)) $(GENERATED_DEFINES)

warp.o : $(SRCS)
	$(DC) $(DFLAGS) $(OFSYNTAX)$@ $(SRCS)

warp : warp.o
	gcc -m64 -Bthird-party2/binutils/2.21.1/centos6-native/da39a3e/bin/gold -Bthird-party2/glibc/2.17/gcc-4.8.1-glibc-2.17-fb/99df8fc/lib -L/home/aalexandre/bin/../d/phobos/generated/linux/release/default -l:libphobos2.a -lpthread -lm -lrt -o $@ $^

$(WARPDRIVE) : warpdrive.d $(GENERATED_DEFINES)
	$(DC) $(DFLAGS) $(OFSYNTAX)$@ $^

$(GENERATED_DEFINES) :
	./builtin_defines.sh '$(CC) $(CFLAGS)' '$(CXX) $(CXXFLAGS)' >$@.tmp
	mv $@.tmp $@
