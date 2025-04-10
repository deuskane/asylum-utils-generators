# Test suite Makefile
# Part of SDCC - http://sdcc.sourceforge.net/
# Michael Hope <michaelh@juju.net.nz> 2001
#
# This Makefile builds and runs the test suites under tests/ for each
# one of the supported ports located under ports/.  The test suite
# results are summarised and individual test failures are logged.  The
# expected result is a single line per port summarising the number of
# failures, test points, and test cases.  The philosophy is that
# checked in code should always pass the suite with no failures, as
# then if there are failures then it is in the current developers code.
#
# Only the required suites are run.  Changing sdcc causes all to be
# re-run.  Changing one suite causes just that to be run.  Changing
# one of the library files should cause all to re-run

# Dependancies:
#   * The sdcc-extra package, available from svn.
#       o svn co https://sdcc.svn.sourceforge.net/svnroot/sdcc/trunk/sdcc-extra
#       o Provides the emulators
#   * The gbdk-lib package from gbdk.
#       o cvs -d cvs.gbdk.sourceforge.net:/cvsroot/gbdk co gbdk-lib
#       o Proviles mul, div, and include files for the z80 tests.
#   * python 1.5 or above
#   * uCsim for the mcs51 port
#
# The paths below assume that sdcc, sdcc-extra, and gbdk-lib all reside in
# the same directory.

# Old notes:
# Starting at the bottom
# Set of source test suites
# Each source suite is processesd producing multiple device specific test suites.
# Each device specific test suite is compiled.
# Each device specific test suite is run, and the output recorded.
# The output from each device specific test suite derrived from a source
# test suite are collated.

# Uncomment this to show only errors and the summary.
# Comment this out for debugging.
.SILENT:

CC = gcc
CFLAGS = -pipe -ggdb -g3 -O0
CPPFLAGS =  -DNO_VARARGS
EXEEXT = .exe

# support VPATH:

srcdir       = .
top_srcdir   = ../..
top_builddir = ../..

# All original tests live in TESTS_DIR and below
TESTS_DIR = $(srcdir)/tests
TESTS_NAME = $(TESTS_DIR)
# All suite results go in RESULTS_DIR
RESULTS_DIR = results
# All data relating to supported ports live in their own directory
# under PORTS_DIR.
PORTS_DIR = $(srcdir)/ports

# Itermediate data directories
# Directory that generated cases and the related object code go.
CASES_DIR = gen

# Script that takes a source test suite and generates the iterations
GENERATE_CASES = $(srcdir)/generate-cases.py

# Magically generate the list of configured ports to test.
# Each directory under ports/ is used as a port name.  Each port is tested.
# Each port must have a spec.mk which describes how to build the object
# files and how to run the emulator.
ALL_PORTS = $(filter-out .svn xa51 z80 gbz80 pic16 pic14 mcs51-common,$(notdir $(wildcard $(PORTS_DIR)/*)))

# These  ports will be cleaned with 'make clean'
CLEAN_PORTS = $(filter-out .svn mcs51-common,$(notdir $(wildcard $(PORTS_DIR)/*)))

MAKE_LIBRARY =

all: test-ports

# Test all of the ports
test-ports:
	for i in $(ALL_PORTS); do $(MAKE) make_library test-port PORT=$$i; done

# Helper rule for testing the z80 port only
test-z80:
	$(MAKE) test-port PORT=z80

# Helper rule for testing the z80 port only
test-gbz80:
	$(MAKE) test-port PORT=gbz80

# Helper rule for testing the mcs51 port only
test-mcs51: test-mcs51-small test-mcs51-medium test-mcs51-large test-mcs51-huge test-mcs51-stack-auto test-mcs51-xstack-auto

test-mcs51-small:
	$(MAKE) test-port PORT=mcs51-small

test-mcs51-medium:
	$(MAKE) test-port PORT=mcs51-medium

test-mcs51-large:
	$(MAKE) test-port PORT=mcs51-large

test-mcs51-huge:
	$(MAKE) make_library test-port PORT=mcs51-huge

test-mcs51-stack-auto:
	$(MAKE) test-port PORT=mcs51-stack-auto

test-mcs51-xstack-auto:
	$(MAKE) make_library test-port PORT=mcs51-xstack-auto

# Helper rule for testing the ds390 port only
test-ds390:
	$(MAKE) test-port PORT=ds390

# Helper rule for testing the z80 port only(use ucSim simulator)
test-ucz80:
	$(MAKE) test-port PORT=ucz80

# Helper rule for testing the hc08 port only(use ucSim simulator)
test-hc08:
	$(MAKE) test-port PORT=hc08

# Helper rule for testing the xa51 port only(use ucSim simulator)
test-xa51:
	$(MAKE) test-port PORT=xa51

# Helper rule for testing the pic16 port only(use gpsim simulator)
test-pic16:
	$(MAKE) test-port PORT=pic16

# Helper rule for testing the pic14 port only(use gpsim simulator)
test-pic14:
	$(MAKE) test-port PORT=pic14

### Helper rule for testing the host cc only
test-host:
	$(MAKE) test-port PORT=host

test-host2:
	$(MAKE) test-port PORT=host

# Begin per-port rules
# List of all of the known source test suites.
ALL_TESTS = $(shell find $(TESTS_DIR) -name "*.c" | sort)

# Intermediate directory
PORT_CASES_DIR = $(CASES_DIR)/$(PORT)
PORT_RESULTS_DIR = $(RESULTS_DIR)/$(PORT)
# Each test generates a result log file
PORT_RESULTS = $(ALL_TESTS:$(TESTS_DIR)/%.c=$(PORT_RESULTS_DIR)/%.out)

SDCC_EXTRA_DIR = $(top_builddir)/../sdcc-extra

# Defaults.  Override in spec.mk if required.
# Path to SDCC
ifdef SDCC_BIN_PATH
  SDCC = $(SDCC_BIN_PATH)/sdcc$(EXEEXT)
else
  SDCC = $(top_builddir)/bin/sdcc$(EXEEXT)
  INC_DIR ?= $(top_srcdir)/device/include
endif
# Base flags.
SDCCFLAGS += --fverbose-asm -DNO_VARARGS
# Extension of object intermediate files
OBJEXT = .rel
# Extension of files that can be run in the emulator
BINEXT = .bin
# Currently unused.  Extension to append to intermediate directories.
DIREXT =

# Only include if we're in a per-port call.
ifdef PORT
  # iclude ./$(PORT)/spec.mk if exists, else include $(PORTS_DIR)/$(PORT)/spec.mk
  ifeq ($(shell if test -f ./ports/$(PORT)/spec.mk; then echo OK; fi),OK)
    include ./ports/$(PORT)/spec.mk
  else
    include $(PORTS_DIR)/$(PORT)/spec.mk
  endif
endif

make_library: $(MAKE_LIBRARY)

SDCCFLAGS += -I$(srcdir)/fwk/include -I$(srcdir)/tests
ifdef INC_DIR
  SDCCFLAGS += -I$(INC_DIR)
endif

# List of intermediate files to keep.  Pretty much keep everything as
# disk space is free.
.PRECIOUS: $(PORT_CASES_DIR)/% %$(OBJEXT) %$(EXEEXT) %$(BINEXT)

# Rule to generate the iterations of a test suite off the soure suite.
$(PORT_CASES_DIR)/%/iterations.stamp: $(TESTS_DIR)/%.c $(GENERATE_CASES)
	echo Processing $(notdir $<)
	rm -rf $(dir $@)
	mkdir -p $(dir $@)
	python $(GENERATE_CASES) $< $(dir $@) > /dev/null
	touch $@

# Rule linking the combined results log to all of the files in the
# iteration directory.
$(PORT_RESULTS_DIR)/%.out: $(PORT_CASES_DIR)/%/iterations.stamp
	$(MAKE) iterations PORT=$(PORT) CASES=$(dir $<)

# Rule to summaries the results for one port after all of the tests
# have been run.
port-results: port-dirs $(PORT_RESULTS)
	echo Summary for \'$(PORT)\': `cat $(PORT_RESULTS) | python $(srcdir)/collate-results.py`
	echo

port-dirs:
	mkdir -p $(PORT_CASES_DIR) $(PORT_RESULTS_DIR)
	echo Running $(PORT) regression tests

test-port: port-results

# Begin rules that process each iteration generated from the source
# test

# List of all of the generated iteration source files.
SUB_CASES = $(sort $(wildcard $(CASES)*.c))
# List of all the sub result logs generated from the iterations.
SUB_RESULTS = $(SUB_CASES:%.c=%.out)
# Overall target.  Concatenation of all of the sub results.
RESULTS = $(CASES:$(CASES_DIR)/%/$(DIREXT)=$(RESULTS_DIR)/%.out)

iterations: $(RESULTS)

# Rule to generate the overall target from the sub results.
$(RESULTS): $(SUB_RESULTS)
	cat $(SUB_RESULTS) > $@

# The remainder of the rules are in $PORT/spec.mk.  The port needs to
# be able to turn an iterated test suite into a sub result, normally
# by:
#    1. Compile the required library files
#    2. Compile this test suite.
#    3. Link 1, 2, and any required stdlib into an executable.
#    4. Run the executable inside an emulator, and capture the text
#    output into %.out.
#
# The emulator must exit when main() returns.

# BeginGeneric rules

clean:
	rm -rf $(CASES_DIR) $(RESULTS_DIR) *.pyc
	for i in $(CLEAN_PORTS); do $(MAKE) -f $(PORTS_DIR)/$$i/spec.mk _clean PORTS_DIR=$(PORTS_DIR) PORT=$$i; done

distclean: clean
	rm -f Makefile
