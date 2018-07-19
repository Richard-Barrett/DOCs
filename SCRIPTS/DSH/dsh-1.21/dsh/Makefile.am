## $Id: Makefile.am,v 1.7 2005/07/07 21:31:13 lile Exp $

INCLUDES =	$(RL_CFLAGS)

bin_PROGRAMS =	dsh

dsh_SOURCES =	\
		collective.c \
		debug.c \
		dsh.c \
		print.c \
		proc.c \
		queue.c	\
		resolv.c \
		usage.c

dsh_LDADD =	$(RL_LIBS)

noinst_HEADERS = \
		collective.h \
		debug.h \
		dsh.h \
		includes.h\
		print.h \
		proc.h \
		queue.h \
		resolv.h \
		usage.h

man_MANS = dsh.1
		
EXTRA_DIST = dsh.1.in

CLEANFILES = dsh.1

edit = sed \
        -e 's,@bindir\@,$(bindir),g' \
        -e 's,@VERSION\@,$(VERSION),g'

dsh.1: Makefile $(srcdir)/dsh.1.in
	rm -f dsh.1
	$(edit) $(srcdir)/dsh.1.in > dsh.1
