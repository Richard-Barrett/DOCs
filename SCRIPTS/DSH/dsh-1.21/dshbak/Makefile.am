## $Id: Makefile.am,v 1.3 2005/07/20 20:19:24 lile Exp $

bin_SCRIPTS = dshbak

EXTRA_DIST = dshbak.pl dshbak.1.in

BUILT_SOURCES = dshbak

man_MANS = dshbak.1
		
CLEANFILES = dshbak dshbak.1

## This is a temporary placeholder until I either
## setup the Makefile.PL magic or autoconf the perl
## bits
dshbak: Makefile dshbak.pl
	rm -f dshbak
	cp $(srcdir)/dshbak.pl dshbak.tmp
	mv dshbak.tmp dshbak
	chmod +x dshbak

edit = sed \
        -e 's,@bindir\@,$(bindir),g' \
        -e 's,@VERSION\@,$(VERSION),g'

dshbak.1: Makefile $(srcdir)/dshbak.1.in
	rm -f dshbak.1
	$(edit) $(srcdir)/dshbak.1.in > dshbak.1
