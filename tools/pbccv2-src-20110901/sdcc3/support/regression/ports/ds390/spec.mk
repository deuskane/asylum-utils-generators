# Regression test specification for the ds390 target running with uCsim

CC_FOR_BUILD = $(CC)

# path to uCsim
ifdef SDCC_BIN_PATH
  S51 = $(SDCC_BIN_PATH)/s51$(EXEEXT)
else
  S51A = $(top_builddir)/sim/ucsim/s51.src/s51$(EXEEXT)
  S51B = $(top_builddir)/bin/s51$(EXEEXT)

  S51C = $(shell if [ -f $(S51A) ]; then echo $(S51A); else echo $(S51B); fi)

ifndef CROSSCOMPILING
  SDCCFLAGS += --nostdinc -I$(top_srcdir)
  LINKFLAGS += --nostdlib -L$(top_builddir)/device/lib/build/ds390
endif
endif

ifdef CROSSCOMPILING
  DEV_NULL ?= NUL
  SDCCFLAGS += -I$(top_srcdir)

  S51 = wine $(S51C)
else
  DEV_NULL ?= /dev/null

  S51 = $(S51C)
endif

SDCCFLAGS +=-mds390 --less-pedantic -DREENTRANT=__reentrant -Wl-r
LINKFLAGS += libds390.lib libsdcc.lib liblong.lib libint.lib libfloat.lib

OBJEXT = .rel
BINEXT = .ihx

# otherwise `make` deletes testfwk.o and `make -j` will fail
.PRECIOUS: $(PORT_CASES_DIR)/%$(OBJEXT)

# Required extras
EXTRAS = $(PORT_CASES_DIR)/testfwk$(OBJEXT) $(PORT_CASES_DIR)/support$(OBJEXT)

# Rule to link into .ihx
%$(BINEXT): %$(OBJEXT) $(EXTRAS)
	$(SDCC) $(SDCCFLAGS) $(LINKFLAGS) $(EXTRAS) $< -o $@

%$(OBJEXT): %.c
	$(SDCC) $(SDCCFLAGS) -c $< -o $@

$(PORT_CASES_DIR)/%$(OBJEXT): $(PORTS_DIR)/$(PORT)/%.c
	$(SDCC) $(SDCCFLAGS) -c $< -o $@

$(PORT_CASES_DIR)/%$(OBJEXT): fwk/lib/%.c
	$(SDCC) $(SDCCFLAGS) -c $< -o $@

# run simulator with 25 seconds timeout
%.out: %$(BINEXT) $(CASES_DIR)/timeout
	mkdir -p $(dir $@)
	-$(CASES_DIR)/timeout 25 $(S51) -tds390 -S in=$(DEV_NULL),out=$@ $< < $(PORTS_DIR)/ds390/uCsim.cmd > $(@:.out=.sim) || \
          echo -e --- FAIL: \"timeout, simulation killed\" in $(<:$(BINEXT)=.c)"\n"--- Summary: 1/1/1: timeout >> $@
	python $(srcdir)/get_ticks.py < $(@:.out=.sim) >> $@
	-grep -n FAIL $@ /dev/null || true

$(CASES_DIR)/timeout: fwk/lib/timeout.c
	$(CC_FOR_BUILD) $(CFLAGS) $< -o $@

_clean:
