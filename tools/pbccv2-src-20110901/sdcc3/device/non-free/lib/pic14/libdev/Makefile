SDCC_BASE = ../../../../..
INSTALL_DIR = ../bin


srcdir = .

CC = $(SDCC_BASE)/bin/sdcc
LIB = gplib
CP = cp
RM = rm -f
RMDIR = rmdir

CPPFLAGS = -I$(srcdir)/../../../../include/pic14 -I$(srcdir)/../../../../non-free/include/pic14

C_SRC = $(notdir $(wildcard $(srcdir)/pic1*.c))
OBJS = $(C_SRC:.c=.o)
LIBS = $(addprefix $(INSTALL_DIR)/,$(OBJS:.o=.lib))

all : $(LIBS)

ifeq (0,1)
# useful while fixing .inc files
GPUTILS = /opt/modules/gputils-0.13.3/share/gputils
pic%.c : $(GPUTILS)/header/p%.inc
	-$(SDCC_BASE)/support/scripts/inc2h.pl $* $(GPUTILS);
	-mv pic$*.h $(SDCC_BASE)/device/non-free/include/pic/pic$*.h;
endif

pic%.o : pic%.c
ifndef SILENT
	@echo "[  CC   ] ==> $(patsubst $(top_builddir)/%,%,$@)"
endif
	@-$(CC) -mpic14 -p$* $(CPPFLAGS) $(CFLAGS) -o "$@" -c "$<"

$(INSTALL_DIR)/%.lib : %.o
	@-$(LIB) -c "$@" "$<";

install : all

clean : clean-intermediate
	@-$(RM) *.asm
	@-$(RM) $(OBJS) $(LIBS)
	@-$(RMDIR) ../build/libdev

distclean: clean
	@-$(RM) Makefile

clean-intermediate :
	@-$(RM) *.lst *.d *.adb

