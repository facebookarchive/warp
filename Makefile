# Figure out which compiler to use (prefer gdc, fall back to dmd).
DC:=$(shell which gdc 2>/dev/null)
ifeq (,$(DC))
DC:=dmd
DFLAGS=-O -inline -release
VERSION=-version=$1
else
DFLAGS=-O4 -frelease -fno-bounds-check -fbuiltin
VERSION=-fversion=$1
endif

# warp sources
SRCS=cmdline.d constexpr.d context.d directive.d expanded.d file.d		\
id.d lexer.d loc.d macros.d main.d number.d outdeps.d ranges.d skip.d	\
sources.d stringlit.d textbuf.d

# Binaries generated
BIN=warp warpdrive_gcc4_7_1 warpdrive_gcc4_8_1 warpdrive_clang3_2 \
      warpdrive_clang3_4 warpdrive_clangdev

# Rules

all : $(BIN)

clean :
	rm -rf $(BIN) warp.o warpdrive_*.o

warp : $(SRCS)
	$(DC) $(DFLAGS) -of$@ $(SRCS)

warpdrive_gcc4_7_1 : warpdrive.d defines_gcc4_7_1.d defines_gxx4_7_1.d
	$(DC) $(DFLAGS) $(call VERSION,gcc4_7_1) -of$@ $^

warpdrive_gcc4_8_1 : warpdrive.d defines_gcc4_8_1.d defines_gxx4_8_1.d
	$(DC) $(DFLAGS) $(call VERSION,gcc4_8_1) -of$@ $^

warpdrive_clang3_2 : warpdrive.d defines_clang3_2.d defines_clangxx3_2.d
	$(DC) $(DFLAGS) $(call VERSION,clang3_2) -of$@ $^

warpdrive_clang3_4 : warpdrive.d defines_clang3_4.d defines_clangxx3_4.d
	$(DC) $(DFLAGS) $(call VERSION,clang3_4) -of$@ $^

warpdrive_clangdev : warpdrive.d defines_clangdev.d defines_clangxxdev.d
	$(DC) $(DFLAGS) $(call VERSION,clangdev) -of$@ $^
