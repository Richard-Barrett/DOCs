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
 * $Id: queue.h,v 1.10 2005/07/20 00:12:23 lile Exp $
 */

#ifndef _queue_h
#define _queue_h

typedef struct process
{
	struct member	*member;
	pid_t		 pid;
	int		 status,
			 done,
			 signal,
			 pstdin,
			 pstdout,
			 pstderr,
			 outcount,
			 errcount;
	char		*name,
			*outbuffer,
			*errbuffer;
	struct process	*prev,
			*next;
	char		**argv;
	time_t		 watchdog,
			 timer;
} process_t;

int queue_max_slots(int);
int queue_slots(void);
int queue_load(void);
int queue_insert(struct member *, char *, int, char **);
int queue_delete(struct process *);
int queue_run(int, int);
int queue_set_watchdogs(time_t);

#endif /* _queue_h */
