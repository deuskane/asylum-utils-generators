#
# uCsim gui.src/Makefile
#
# (c) Drotos Daniel, Talker Bt. 1999
#

SHELL		= /bin/sh
CXX		= g++
CPP		= gcc -E
CXXCPP		= g++ -E
RANLIB		= ranlib
INSTALL		= /usr/bin/install -c
MAKEDEP         = g++ -MM

top_builddir	= ..
top_srcdir	= ..

DEFS            = $(subs -DHAVE_CONFIG_H,,-DHAVE_CONFIG_H)
CPPFLAGS        =  -I$(srcdir) -I$(top_builddir) -I$(top_srcdir) \
		  -I$(top_srcdir)/sim.src -I$(top_srcdir)/cmd.src
CFLAGS          = -g -O2 -Wall
CXXFLAGS        = -g -O2 -g -Wall

LIBS		=   -L$(top_builddir)

curses_ok	= no

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
srcdir          = .


enable_serio	= no
PKGS		=
ifeq ($(enable_serio),yes)
SERIO_PKG	= serio.src
else
SERIO_PKG	=
endif
CURSES_PKGS	= $(SERIO_PKG)

# Common code
OBJECTS		= rec.o
SOURCES		= $(patsubst %.o,%.cc,$(OBJECTS))

# uCsim only
UCSIM_OBJECTS	= gui.o if.o
UCSIM_SOURCES	= $(patsubst %.o,%.cc,$(UCSIM_OBJECTS))

# Tool only
TOOL_OBJECTS	=
TOOL_SOURCES	= $(patsubst %.o,%.cc,$(TOOL_OBJECTS))

ALL_SOURCES	= $(SOURCES) $(UCSIM_SOURCES) $(TOOL_SOURCES)


# Compiling entire program or any subproject
# ------------------------------------------
all: gui.src

gui.src: checkconf gui_api
ifeq ($(curses_ok),yes)
ifneq ($(CURSES_PKGS),)
	@for pkg in $(CURSES_PKGS); do\
	  $(MAKE) -C $$pkg $$pkg;\
	done
endif
endif
#	@for pkg in $(PKGS); do\
#	  $(MAKE) -C $$pkg $$pkg ;\
#	done

gui_api: ucsim_lib tool_lib


# Compiling and installing everything and runing test
# ---------------------------------------------------
install: install_gui_api
ifeq ($(curses_ok),yes)
ifneq ($(CURSES_PKGS),)
	@for pkg in $(CURSES_PKGS); do\
	  $(MAKE) -C $$pkg install ; cd ..;\
	done
endif
endif

install_gui_api:


# Deleting all the installed files
# --------------------------------
uninstall: uninstall_gui_api
ifeq ($(curses_ok),yes)
ifneq ($(CURSES_PKGS),)
	@for pkg in $(CURSES_PKGS); do\
	  $(MAKE) -C $$pkg uninstall ; cd ..;\
	done
endif
endif

uninstall_gui_api:


# Performing self-test
# --------------------
check: check_local
ifneq ($(CURSES_PKGS),)
	@for pkg in $(CURSES_PKGS); do\
	  $(MAKE) -C $$pkg check;\
	done
endif

check_local:

test: test_local
ifneq ($(CURSES_PKGS),)
	@for pkg in $(CURSES_PKGS); do\
	  $(MAKE) -C $$pkg test;\
	done
endif

test_local:


# Performing installation test
# ----------------------------
installcheck: installcheck_gui_api
ifneq ($(CURSES_PKGS),)
	@for pkg in $(CURSES_PKGS); do\
	  $(MAKE) -C $$pkg installcheck;\
	done
endif

installcheck_gui_api:


# Creating installation directories
# ---------------------------------
installdirs:
ifneq ($(CURSES_PKGS),)
	@for pkg in $(CURSES_PKGS); do\
	  $(MAKE) -C $$pkg installdirs;\
	done
endif

# Creating dependencies
# ---------------------
dep: Makefile.dep

Makefile.dep: $(ALL_SOURCES) $(srcdir)/*.h
	$(MAKEDEP) $(CPPFLAGS) $(filter %.cc,$^) >Makefile.dep

# don't include Makefile.dep for the listed targets:
ifeq "$(findstring $(MAKECMDGOALS),uninstall uninstall_gui_api \
                                   check check_local test test_local \
                                   checkconf \
                                   clean_local clean distclean_local \
                                   distclean mostlyclean realclean)" ""
  -include Makefile.dep
endif
include $(srcdir)/clean.mk


# My rules
# --------
ucsim_lib: $(top_builddir)/libguiucsim.a

$(top_builddir)/libguiucsim.a: $(OBJECTS) $(UCSIM_OBJECTS)
	ar -rcu $*.a $(OBJECTS) $(UCSIM_OBJECTS)
	$(RANLIB) $*.a

tool_lib: $(top_builddir)/libguitool.a

$(top_builddir)/libguitool.a: $(OBJECTS) $(TOOL_OBJECTS)
	ar -rcu $*.a $(OBJECTS) $(TOOL_OBJECTS)
	$(RANLIB) $*.a

.cc.o:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c $< -o $@


# Remaking configuration
# ----------------------
checkconf:
	@if [ -f $(top_builddir)/devel ]; then\
	  $(MAKE) -f conf.mk srcdir="$(srcdir)" top_builddir="$(top_builddir)" freshconf;\
	fi

# End of gui.src/Makefile
