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
 * $Id: collective.c,v 1.17 2005/10/18 01:20:45 lile Exp $
 */

#include "includes.h"

RCSID("$Id: collective.c,v 1.17 2005/10/18 01:20:45 lile Exp $");

struct member	*collective = (struct member *)NULL;

int		 collective_count = 0;

struct member *
collective_get_next(struct member *ptr)
{
	if (ptr == (struct member *)NULL)
		return collective;
	if (ptr)
		return ptr->next;
	return (struct member *)NULL;
}

void
free_collective(void)
{
	struct member	*ptr = collective,
			*next = (struct member *)NULL;

	while (ptr)
	{
		next = ptr->next;

		if (ptr->name)
		{
			free(ptr->name);
			ptr->name = (char *)NULL;
		}
		if (ptr->reliable)
		{
			free(ptr->reliable);
			ptr->reliable = (char *)NULL;
		}
		free(ptr);
		ptr = next;
	}
	collective = (struct member *)NULL;
}

int
collective_drop_member(struct member *ptr)
{
	struct member	*prev,
			*next;

	prev = ptr->prev;
	next = ptr->next;

	if (collective == ptr)
		collective = next;

	if (next)
		next->prev = prev;
	if (prev)
		prev->next = next;

	if (ptr->name)
	{
		free(ptr->name);
		ptr->name = (char *)NULL;
	}
	if (ptr->reliable)
	{
		free(ptr->reliable);
		ptr->reliable = (char *)NULL;
	}
	free(ptr);
	return 0;
}

int
collective_add_member(char *name)
{
	char 		*reliable;
	struct member	*member;

	debug_msg("collective_add_member(%s)\n", (name ? name : "NULL"));

	if (!name || *name == '\0')
		return 1;

	if (*name == '@' )
	{
		char **netgroup;
		if ((netgroup = resolv_netgroup(name)) != (char **)NULL)
		{
			char **ptr = netgroup;
			while (*ptr)
			{
				collective_add_member(*ptr);
				free(*ptr);
				*ptr=(char *)NULL;
				ptr++;
			}
			free(netgroup);
			netgroup = (char **)NULL;
		}
		return 0;
	} else {
		if ((reliable = resolv_host(name)) != (char *)NULL)
		{
			member = malloc(sizeof(struct member));
			memset(member, '\0', sizeof(struct member));
			member->name = strdup(name);
			member->reliable = strdup(reliable);
			member->responding = 1;
		} else {
			if (!qflag)
				print_host_error(name, "unknown host\n");
			return 1;
		}
	}

	if (collective)
	{
		struct member	*ptr,
				*prev;
		ptr = collective;
		do
		{
			if (!strcmp(member->reliable, ptr->reliable))
			{
				debug_msg("collective_add_member - dropping duplicate\n");
				free(member);
				member = (struct member *)NULL;
				return 0;
			}
			prev = ptr;
			ptr = ptr->next;
		} while (ptr);
		prev->next = member;
		member->prev = prev;
	} else {
		collective = member;
	}
	collective_count++;

	return 0;
}

int
collective_parse(char *buffer, char separator)
{
	char	*tmp,
		*ptr,
		*s;

	if (!buffer)
		return 0;

	tmp = strdup(buffer);
	ptr = tmp;

	while (ptr)
	{
		char *sep;
		if ((sep = strchr(ptr, separator)))
			*sep++ = '\0';
		if ((s = clean_string(ptr)) != NULL && *s != '#' && strlen(s))
			collective_add_member(s);
		ptr = sep;
	}
	free(tmp);
	tmp = (char *)NULL;
	return 0;
}

int
collective_display(void)
{
	struct member	*ptr = collective;
	int		 count = 0;

	while (ptr)
	{
		if (cflag || ptr->responding)
			count++;
		ptr = ptr->next;
	}

	ptr = collective;
	printf("working collective (%d):", count);
	while (ptr)
	{
		if (cflag || ptr->responding)
			printf("%s%s", (ptr == collective ? " " : ", "), ptr->name);
		ptr = ptr->next;
	}
	if (qflag)
		printf("\nfanout: %d", fflag);
	printf("\n");

	return 0;
}

int
collective_add_file(FILE *file)
{
	int		 fd = fileno(file);
	char		*baddr;
	struct stat	 sb;

	if (fstat(fd, &sb) != 0)
	{
		perror("stat");
		exit(1);
	}

	if ((baddr = (char *)mmap(0, sb.st_size, PROT_READ | PROT_WRITE, MAP_PRIVATE,
	    fd, 0)) == MAP_FAILED)
	{
		perror("mmap");
		exit(1);
	}

	collective_parse(baddr, '\n');

	if (munmap(baddr, sb.st_size) == -1)
	{
		perror("munmap");
		exit(1);
	}

	return 0;
}

int
collective_add_stdin(FILE *file)
{
	char	 *wcoll = (char *)NULL;
	int	 fd = fileno(file),
		 count = 0,
		 tmp;

	do {
		char	 readbuffer[1024],
			*tmpbuffer;

		if ((tmp = read(fd, &readbuffer, sizeof(readbuffer))) > 0)
		{
			tmpbuffer = (char *)malloc(sizeof(char) * (count + tmp + 1));
			memset(tmpbuffer, '\0', sizeof(char) * (count + tmp + 1));
			if (wcoll)
			{
				memcpy(tmpbuffer, wcoll, sizeof(char) * count);
				free(wcoll);
				wcoll = (char *)NULL;
			}
			wcoll = tmpbuffer;
			memcpy(wcoll + count, readbuffer, sizeof(char) * tmp);
			count += tmp;
			
		}
	} while (tmp > 0);

	collective_parse(wcoll, '\n');

	free(wcoll);
	wcoll = (char *)NULL;

	return 0;
}
