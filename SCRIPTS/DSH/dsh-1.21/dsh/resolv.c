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
 * $Id: resolv.c,v 1.9 2005/07/20 00:12:23 lile Exp $
 */

#include "includes.h"

RCSID("$Id: resolv.c,v 1.9 2005/07/20 00:12:23 lile Exp $");

char *
resolv_host(char *name)
{
	struct hostent		 *hp;
	struct sockaddr_in	 addr;

	if (!name || *name == '\0' || *name == '@')
		return (char *)NULL;

	memset((char *)&addr, '\0', sizeof(addr));
	if (inet_aton(name, &addr.sin_addr) == 1) {
		return name;
	} else {
		if ((hp = gethostbyname(name)) == NULL)
			return (char *)NULL;
	}

	return hp->h_name;
}

char **
resolv_netgroup(char *name)
{
	static char **netgroup = (char **)NULL;
	char	 *group = (char *)NULL,
		 *host,
		 *user,
		 *domain;
	int	  i = 0;

	if (!name || *name == '\0')
		return (char **)NULL;

	if (netgroup) {
		char **ptr = netgroup;
		while(*ptr)
		{
			free(*ptr);
			*ptr = NULL;
			ptr++;
		}
		free(netgroup);
		netgroup = (char **)NULL;
	}

	if (*name == '@')
		group = strdup((name + 1));
	else
		group = strdup(name);

	setnetgrent(group);
	while (getnetgrent(&host, &user, &domain))
	{
		char **tmp;
		tmp = (char **)malloc(sizeof(char *) * (i + 2));
		if (netgroup)
		{
			memcpy(tmp, netgroup, sizeof(char *) * i);
			free(netgroup);
			netgroup = (char **)NULL;
		}
		netgroup = tmp;
		netgroup[i++] = strdup(host);
		netgroup[i] = (char *)NULL;
	}
	endnetgrent();

	free(group);
	group = (char *)NULL;

	return netgroup;

}
