/*
 * Copyright (c) 2004, 2005, Larry Lile <lile@users.sourceforge.net>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice unmodified, this list of conditions, and the following
 *    disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * $Id: print.c,v 1.8 2005/07/20 00:12:23 lile Exp $
 */

#include "includes.h"

RCSID("$Id: print.c,v 1.8 2005/07/20 00:12:23 lile Exp $");

int
print_error(char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	return 0;
}

int
print_host(FILE *file, char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	if (get_debug() && file == stderr)
		vfprintf(stdout, fmt, ap);
	else
		vfprintf(file, fmt, ap);
	va_end(ap);
	return 0;
}

int
print_host_error(char *name, char *buffer)
{
	char		*ptr = (char *)NULL,
			*out = (char *)NULL;
	unsigned int	 count = 0;

	if (!name || *name == '\0')
		return 0;

	if (buffer)
		out = strdup(buffer);

	ptr = out;
	do
	{
		char *sep;
		if ((sep = strchr(ptr, '\n')))
		{
			*sep++ = '\0';
			count = sep - out;
			print_host(stdout, "%-16s: %s\n", name, ptr);
		}
		ptr = sep;
	} while (ptr);

	free(out);

	return count;
}
