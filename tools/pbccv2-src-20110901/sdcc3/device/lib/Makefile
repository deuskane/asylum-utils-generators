#
#
#

VERSION         = 3.0.1
VERSIONHI       = 3
VERSIONLO       = 0
VERSIONP        = 1

SHELL           = /bin/sh
INSTALL         = /usr/bin/install -c
CP              = cp
AR_S            = ar -S

LIB_TYPE        = RANLIB

ifeq ($(shell uname -s),Linux)
CP_U    = $(CP) -u
else
CP_U    = $(CP)
endif

top_builddir    = ../..
top_srcdir      = ../..

srcdir          = .
INCDIR          = $(top_srcdir)/device/include
ifndef PORTINCDIR
PORTINCDIR      = $(INCDIR)/mcs51
endif

CC              = $(top_builddir)/bin/sdcc
CPP             = $(top_builddir)/bin/sdcpp

prefix          = /usr/local
exec_prefix     = ${prefix}
bindir          = ${exec_prefix}/bin
libdir          = ${exec_prefix}/lib
datadir         = ${datarootdir}
datarootdir     = ${prefix}/share
includedir      = ${prefix}/include
mandir          = ${datarootdir}/man
man1dir         = $(mandir)/man1
man2dir         = $(mandir)/man2
infodir         = ${datarootdir}/info

lib_dir_suffix  = sdcc/lib

sdcc_libdir     = $(DESTDIR)$(datadir)/$(lib_dir_suffix)

CPPFLAGS        = -I$(INCDIR) -I$(PORTINCDIR)
CFLAGS          = $(MODELFLAGS) --nostdinc --std-c99

BUILDDIR        = build
# Default
PORT            = z80
ifndef PORTDIR
PORTDIR         = $(BUILDDIR)/$(PORT)
endif

OPT_DISABLE_AVR   = 1
OPT_DISABLE_DS390 = 1
OPT_DISABLE_DS400 = 1
OPT_DISABLE_GBZ80 = 1
OPT_DISABLE_HC08  = 1
OPT_DISABLE_MCS51 = 1
OPT_DISABLE_PIC14 = 1
OPT_DISABLE_PIC16 = 1
OPT_DISABLE_XA51  = 1
OPT_DISABLE_Z80   = 1

SOURCES_FLOAT = $(COMMON_FLOAT) \
  _fscmp.c \
  _fsget1arg.c \
  _fsget2args.c \
  _fsnormalize.c \
  _fsreturnval.c \
  _fsrshift.c \
  _fsswapargs.c \
  _logexpf.c

SOURCES_INT = $(COMMON_INT) \
  _divsint.c \
  _divuint.c \
  _modsint.c \
  _moduint.c \
  _mulint.c

SOURCES_LONG = $(COMMON_LONG) \
  _divulong.c \
  _mullong.c

SOURCES_SDCC = $(COMMON_SDCC) \
  _autobaud.c \
  _bp.c \
  _decdptr.c \
  _gptrget.c \
  _gptrgetc.c \
  _gptrput.c \
  _ser.c \
  _setjmp.c \
  serial.c \
  _itoa.c \
  _ltoa.c \
  _spx.c \
  _startup.c \
  _strlen.c \
  _memmove.c \
  _heap.c \
  sprintf.c \
  vprintf.c \
  printf_fast.c \
  printf_fast_f.c \
  printf_tiny.c \
  printfl.c \
  bpx.c

SOURCES = $(SOURCES_FLOAT) $(SOURCES_INT) $(SOURCES_LONG) $(SOURCES_SDCC)

OBJECTS_FLOAT = $(SOURCES_FLOAT:%.c=$(PORT)/%.rel)
OBJECTS_INT = $(SOURCES_INT:%.c=$(PORT)/%.rel)
OBJECTS_LONG = $(SOURCES_LONG:%.c=$(PORT)/%.rel)
OBJECTS_SDCC = $(SOURCES_SDCC:%.c=$(PORT)/%.rel)

OBJECTS = $(OBJECTS_FLOAT) $(OBJECTS_INT) $(OBJECTS_LONG) $(OBJECTS_SDCC)

XA51_FLOAT = $(COMMON_FLOAT)

XA51_INT = $(COMMON_INT) \
  _divsint.c \
  _divuint.c \
  _modsint.c \
  _moduint.c \
  _mulint.c

XA51_LONG = $(COMMON_LONG) \
  _divulong.c \
  _mullong.c

XA51_SDCC = $(COMMON_SDCC) \
  _memmove.c \
  _strlen.c \
  _heap.c

XA51SOURCES = $(XA51_FLOAT) $(XA51_INT) $(XA51_LONG) $(XA51_SDCC)
XA51OBJECTS = $(XA51SOURCES:%.c=$(PORT)/%.rel)

LIB_FILES = $(PORTDIR)/libfloat.lib $(PORTDIR)/libint.lib $(PORTDIR)/liblong.lib $(PORTDIR)/libsdcc.lib

OEXT            = .rel

include $(srcdir)/incl.mk

ifeq ($(OPT_DISABLE_DS390), 0)
TARGETS        += model-ds390
endif

ifeq ($(OPT_DISABLE_DS400), 0)
TARGETS        += model-ds400
endif

ifeq ($(OPT_DISABLE_HC08), 0)
TARGETS        += model-hc08
endif

ifeq ($(OPT_DISABLE_MCS51), 0)
TARGETS        += models small-mcs51-stack-auto
endif

ifeq ($(OPT_DISABLE_PIC14), 0)
TARGETS        += model-pic14
endif

ifeq ($(OPT_DISABLE_PIC16), 0)
TARGETS        += model-pic16
endif

ifeq ($(OPT_DISABLE_Z80), 0)
TARGETS        += model-z80
endif

ifeq ($(OPT_DISABLE_GBZ80), 0)
TARGETS        += model-gbz80
endif

# Compiling entire program or any subproject
# ------------------------------------------
all:
	$(MAKE) checkconf
ifneq ($(TARGETS), )
	$(MAKE) $(TARGETS)
endif

objects:
	$(MAKE) build-dir
	$(MAKE) $(OBJECTS)
	$(MAKE) port-specific-objects
	$(MAKE) $(LIB_FILES)
	$(MAKE) clean_intermediate

models:
	if grep '^mcs51\>' $(top_builddir)/ports.build > /dev/null; then \
	  for model in $(MODELS); do \
	    $(MAKE) MODELFLAGS="--model-$$model" PORT=$$model PORTINCDIR=$(INCDIR)/mcs51 objects; \
	  done \
	fi

small-mcs51-stack-auto:
	if grep '^mcs51\>' $(top_builddir)/ports.build > /dev/null; then \
	  mkdir -p small-stack-auto; cp small/Makefile small-stack-auto; \
	  $(MAKE) MODELFLAGS="--model-small --stack-auto" PORT=small-stack-auto PORTDIR=$(BUILDDIR)/small-stack-auto PORTINCDIR=$(INCDIR)/mcs51 objects; \
	fi

model-mcs51-stack-auto:
	if grep '^mcs51\>' $(top_builddir)/ports.build > /dev/null; then \
	  for model in $(MODELS); do \
	    mkdir -p $${model}-stack-auto; cp $${model}/Makefile $${model}-stack-auto; \
	    $(MAKE) MODELFLAGS="--model-$$model --stack-auto" PORT=$${model}-stack-auto PORTDIR=$(BUILDDIR)/$${model}-stack-auto PORTINCDIR=$(INCDIR)/mcs51 objects; \
	  done \
	fi

model-mcs51-xstack-auto:
	if grep '^mcs51\>' $(top_builddir)/ports.build > /dev/null; then \
	  for model in $(MODELS); do \
	    mkdir -p $${model}-xstack-auto; cp $${model}/Makefile $${model}-xstack-auto; \
	    $(MAKE) MODELFLAGS="--model-$$model --stack-auto --xstack" PORT=$${model}-xstack-auto PORTDIR=$(BUILDDIR)/$${model}-xstack-auto PORTINCDIR=$(INCDIR)/mcs51 objects; \
	  done \
	fi

model-ds390:
	if grep '^ds390\>' $(top_builddir)/ports.build > /dev/null; then \
	  $(MAKE) MODELFLAGS="-mds390" PORT=ds390 PORTINCDIR=$(INCDIR)/mcs51 objects; \
	fi

model-ds400:
	if grep '^ds400\>' $(top_builddir)/ports.build > /dev/null; then \
	  $(MAKE) MODELFLAGS="-mds400" PORT=ds400 PORTINCDIR=$(INCDIR)/mcs51 objects; \
	fi

model-xa51:
	if grep '^xa51\>' $(top_builddir)/ports.build > /dev/null; then \
	  $(MAKE) MODELFLAGS="-mxa51" PORT=xa51 objects-xa51; \
	fi

objects-xa51:
	$(MAKE) build-dir
	$(MAKE) $(XA51OBJECTS)
	$(MAKE) port-specific-objects

$(PORTDIR)/lib$(PORT).lib: $(XA51OBJECTS)
ifeq ($(LIB_TYPE), SDCCLIB)
	../../bin/sdcclib -a $(PORTDIR)/lib$(PORT).lib $(XA51OBJECTS)
else
  ifeq ($(LIB_TYPE), AR)
	$(AR_S) -q $(PORTDIR)/lib$(PORT).lib $(XA51OBJECTS)
  else
    ifeq ($(LIB_TYPE), RANLIB)
	$(AR_S) -q $(PORTDIR)/lib$(PORT).lib $(XA51OBJECTS)
	$(top_builddir)/bin/asranlib $(PORTDIR)/lib$(PORT).lib
    else
	rm -f $(PORTDIR)/lib$(PORT).lib
	for i in $(notdir $(basename $(XA51OBJECTS))); do echo $$i >> $(PORTDIR)/lib$(PORT).lib; done
	cp $(XA51OBJECTS) $(PORTDIR)
    endif
  endif
endif

model-z80:
	if grep '^z80\>' $(top_builddir)/ports.build > /dev/null; then \
	  $(MAKE) MODELFLAGS="-mz80" PORT=z80 objects-z80 OEXT=.o; \
	fi

model-gbz80:
	if grep '^z80\>' $(top_builddir)/ports.build > /dev/null; then \
	  $(MAKE) MODELFLAGS="-mgbz80" PORT=gbz80 objects-z80 OEXT=.o; \
	fi

objects-z80:
	$(MAKE) build-dir
	$(MAKE) port-specific-objects
	$(MAKE) clean_intermediate

model-hc08:
	if grep '^hc08\>' $(top_builddir)/ports.build > /dev/null; then \
	  $(MAKE) MODELFLAGS="-mhc08" PORT=hc08 objects-hc08; \
	fi

objects-hc08:
	$(MAKE) build-dir
	$(MAKE) port-specific-objects
	$(MAKE) clean_intermediate

model-pic16:
	if grep '^pic16\>' $(top_builddir)/ports.build > /dev/null; then \
	  $(MAKE) PORT=pic16 objects-pic16; \
	fi

objects-pic16:
	$(MAKE) build-dir
	$(MAKE) port-specific-objects-pic16
	$(MAKE) clean_intermediate-pic16

model-pic14:
	if grep '^pic14\>' $(top_builddir)/ports.build > /dev/null; then \
	  $(MAKE) PORT=pic14 objects-pic14; \
	fi

objects-pic14:
	$(MAKE) build-dir
	$(MAKE) port-specific-objects-pic14
	$(MAKE) clean_intermediate-pic14

build-dir:
	$(MAKE) $(PORTDIR)
	$(MAKE) $(PORT)

$(PORTDIR):
	mkdir -p $(PORTDIR)

$(PORT):
	mkdir -p $(PORT)

port-specific-objects:
	-if [ -f $(PORT)/Makefile ]; then \
	  $(MAKE) -C $(PORT) PORT=$(PORT); \
	fi

port-specific-objects-pic16:
	-if [ -f $(PORT)/Makefile ]; then \
	  $(MAKE) -C $(PORT); \
	  for i in $(PORT)/*/lib*.a; do cp -f $$i $(PORTDIR)/`basename $$i .a`.lib; done; \
	  cp -f $(PORT)/*/crt0*.o $(PORTDIR); \
	fi

port-specific-objects-pic14:
	-if [ -f $(PORT)/Makefile ]; then \
	  mkdir -p $(PORT)/bin; \
	  $(MAKE) -C $(PORT); \
	  cp -f $(PORT)/bin/*.* $(PORTDIR); \
	fi

ifeq ($(LIB_TYPE), SDCCLIB)

$(PORTDIR)/libfloat.lib: $(OBJECTS_FLOAT)
	../../bin/sdcclib -a $(PORTDIR)/libfloat.lib $(OBJECTS_FLOAT)

$(PORTDIR)/libint.lib: $(OBJECTS_INT)
	../../bin/sdcclib -a $(PORTDIR)/libint.lib $(OBJECTS_INT)

$(PORTDIR)/liblong.lib: $(OBJECTS_LONG)
	../../bin/sdcclib -a $(PORTDIR)/liblong.lib $(OBJECTS_LONG)

$(PORTDIR)/libsdcc.lib: $(OBJECTS_SDCC)
	../../bin/sdcclib -a $(PORTDIR)/libsdcc.lib $(OBJECTS_SDCC)

else
  ifeq ($(LIB_TYPE), AR)

$(PORTDIR)/libfloat.lib: $(OBJECTS_FLOAT)
	$(AR_S) -cq $(PORTDIR)/libfloat.lib $(OBJECTS_FLOAT)

$(PORTDIR)/libint.lib: $(OBJECTS_INT)
	$(AR_S) -cq $(PORTDIR)/libint.lib $(OBJECTS_INT)

$(PORTDIR)/liblong.lib: $(OBJECTS_LONG)
	$(AR_S) -cq $(PORTDIR)/liblong.lib $(OBJECTS_LONG)

$(PORTDIR)/libsdcc.lib: $(OBJECTS_SDCC)
	$(AR_S) -cq $(PORTDIR)/libsdcc.lib $(OBJECTS_SDCC)

  else
    ifeq ($(LIB_TYPE), RANLIB)

$(PORTDIR)/libfloat.lib: $(OBJECTS_FLOAT)
	$(AR_S) -cq $(PORTDIR)/libfloat.lib $(OBJECTS_FLOAT); $(top_builddir)/bin/asranlib $(PORTDIR)/libfloat.lib

$(PORTDIR)/libint.lib: $(OBJECTS_INT)
	$(AR_S) -cq $(PORTDIR)/libint.lib $(OBJECTS_INT); $(top_builddir)/bin/asranlib $(PORTDIR)/libint.lib

$(PORTDIR)/liblong.lib: $(OBJECTS_LONG)
	$(AR_S) -cq $(PORTDIR)/liblong.lib $(OBJECTS_LONG); $(top_builddir)/bin/asranlib $(PORTDIR)/liblong.lib

$(PORTDIR)/libsdcc.lib: $(OBJECTS_SDCC)
	$(AR_S) -cq $(PORTDIR)/libsdcc.lib $(OBJECTS_SDCC); $(top_builddir)/bin/asranlib $(PORTDIR)/libsdcc.lib

    else

$(PORTDIR)/libfloat.lib: $(OBJECTS_FLOAT)
	rm -f $(PORTDIR)/libfloat.lib
	for i in $(notdir $(basename $(OBJECTS_FLOAT))); do echo $$i >> $(PORTDIR)/libfloat.lib; done
	cp $(OBJECTS_FLOAT) $(PORTDIR)

$(PORTDIR)/libint.lib: $(OBJECTS_INT)
	rm -f $(PORTDIR)/libint.lib
	for i in $(notdir $(basename $(OBJECTS_INT))); do echo $$i >> $(PORTDIR)/libint.lib; done
	cp $(OBJECTS_INT) $(PORTDIR)

$(PORTDIR)/liblong.lib: $(OBJECTS_LONG)
	rm -f $(PORTDIR)/liblong.lib
	for i in $(notdir $(basename $(OBJECTS_LONG))); do echo $$i >> $(PORTDIR)/liblong.lib; done
	cp $(OBJECTS_LONG) $(PORTDIR)

$(PORTDIR)/libsdcc.lib: $(OBJECTS_SDCC)
	rm -f $(PORTDIR)/libsdcc.lib
	for i in $(notdir $(basename $(OBJECTS_SDCC))); do echo $$i >> $(PORTDIR)/libsdcc.lib; done
	cp $(OBJECTS_SDCC) $(PORTDIR)

    endif
  endif
endif

clean_intermediate:
	rm -f $(PORTDIR)/*.lst $(PORTDIR)/*.sym

clean_intermediate-pic16:
	$(MAKE) -C $(PORT) clean-intermediate

clean_intermediate-pic14:
	$(MAKE) -C $(PORT) clean-intermediate

# Compiling and installing everything and runing test
# ---------------------------------------------------
install: all installdirs
	[ ! -d "$(BUILDDIR)" ] || $(CP_U) -r $(BUILDDIR)/* $(sdcc_libdir)
	$(CP_U) -r $(MODELS) $(srcdir)/mcs51 $(srcdir)/ds390 $(srcdir)/ds400 \
	                     $(srcdir)/gbz80 $(srcdir)/z80 $(srcdir)/hc08 \
	                     $(srcdir)/pic14 $(srcdir)/pic16 $(srcdir)/*.c $(sdcc_libdir)/src
	$(CP_U) -r $(MODELS) mcs51 ds390 ds400 gbz80 z80 hc08 $(sdcc_libdir)/src

	for src in $(MODELS) ds390 ds400 gbz80 z80 hc08 pic14 pic16; do \
	  find $(sdcc_libdir)/src/$$src -depth \
	    \( -name '*.rel' -o -name '*.dump*' -o -name '*.sym' -o -name '*.o' -o -name '*.lib' -o \
	    -name '*.lst' -o -name '*.asm' -o -name '.svn' -o -name 'autom4te.cache' -o \
	    -name 'build' -o -name 'bin' -o -name 'Makefile*' -o -name 'config*' -o \
	    -name 'depcomp' -o -name 'missing' -o -name 'install-sh' -o \
	    -name 'bootstrap.sh' \) \
	    -exec rm -rf {} + ; \
	done
	find $(sdcc_libdir)/src/mcs51 -depth \
	  \( -name '*.rel' -o -name '*.dump*' -o -name '*.sym' -o -name '*.o' -o -name '*.lib' -o \
	  -name '*.lst' -o -name '.svn' -o -name 'build' -o -name 'bin' -o \
	  -name 'Makefile*' \) \
	  -exec rm -rf {} +

# Deleting all the installed files
# --------------------------------
uninstall:
	rm -rf $(sdcc_libdir)

# Performing self-test
# --------------------
check:


# Performing installation test
# ----------------------------
installcheck:


# Creating installation directories
# ---------------------------------
installdirs:
	for model in $(MODELS); do \
	  mkdir -p $(sdcc_libdir)/$$model; \
	done
	for libdir in small-stack-auto ds390 ds400 hc08 pic16 pic14; do \
	  mkdir -p $(sdcc_libdir)/$$libdir; \
	done
	mkdir -p $(sdcc_libdir)/src

# Creating dependencies
# ---------------------
dep: Makefile.dep

Makefile.dep: $(SOURCES) $(INCDIR)/*.h $(PORTINCDIR)/*.h
	rm -f Makefile.dep
	for i in $(filter %.c,$^); do \
	  $(CPP) -std=c99 -M $(CPPFLAGS) $$i >$${i}.dep; \
	  cat $${i}.dep >>Makefile.dep; \
	  rm $${i}.dep; \
	done

ifeq "$(findstring $(MAKECMDGOALS),uninstall check installcheck installdirs checkconf \
                                   clean distclean mostlyclean realclean)" ""
  -include Makefile.dep
endif
include $(srcdir)/clean.mk

# My rules
# --------

.SUFFIXES: .rel .o

$(PORT)/%$(OEXT): %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

# Remaking configuration
# ----------------------
checkconf:
	@if [ -f $(top_builddir)/devel ]; then\
	  $(MAKE) -f $(srcdir)/conf.mk srcdir="$(srcdir)" top_builddir="$(top_builddir)" \
	  freshconf;\
	fi

# End of main_in.mk/main.mk
