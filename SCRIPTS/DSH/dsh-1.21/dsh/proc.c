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
 * $Id: proc.c,v 1.13 2005/07/20 00:12:23 lile Exp $
 */

#include "includes.h"

RCSID("$Id: proc.c,v 1.13 2005/07/20 00:12:23 lile Exp $");

int	sigchld = -1;

void
proc_sig_child(int signo)
{
	sigchld++;
	debug_msg("child exited (%x)\n", signo);
}

int
proc_reap(struct process *queue)
{
	sigset_t	 newmask,
			 oldmask;
	pid_t	 	 pid = 0;
	int 	 	 status,
			 rc = 0;
	struct process	*ptr;

	if (!queue || !sigchld)
		return 0;

	sigemptyset(&newmask);
	sigaddset(&newmask, SIGCHLD);
	if (sigprocmask(SIG_BLOCK, &newmask, &oldmask) < 0)
		perror("sigprocmask");

	debug_msg("proc_reap() sigchld = %d\n", sigchld);

	while ((pid = waitpid(-1, &status, WNOHANG)) > 0)
	{
		ptr = queue;
		while(ptr)
		{
			if (ptr->pid == pid)
			{
				debug_msg("process %d: exited %d\n",
				    pid, WEXITSTATUS(status));
				ptr->done = 1;
				ptr->status = status;
				ptr = (struct process *)NULL;
				if (status)
					rc++;
			} else {
				ptr = ptr->next;
			}
		}
	}

	sigchld = 0;

	if (sigprocmask(SIG_SETMASK, &oldmask, NULL) < 0)
		perror("sigprocmask");

	return rc;
}

int
proc_output(FILE *file, struct process *proc, char **buffer, int *length, int flush)
{
	char	*tmp = (char *)NULL,
		*out = (char *)NULL;
	int	count = 0;

	debug_msg("proc_output(%s, %s, %p, %d, flush=%d)\n",
			(file == stdout ? "stdout" : "stderr"),
			proc->name, buffer, *length, flush);

	if (*length)
	{
		out = malloc(sizeof(char) * (*length + 1));
		memset(out, '\0', sizeof(char) * (*length + 1));
		memcpy(out, *buffer, *length);
		tmp = out;
		do
		{
			char *sep;
			if ((sep = memchr(tmp, '\n', sizeof(char) * (*length - count))))
			{
				*sep++ = '\0';
				count = sep - out;
				if (strlen(tmp) != 1 || *tmp != '\r')
					print_host(file, "%-16s: %s\n", proc->name, tmp);
			} else {
				if (flush && count < *length)
				{
					print_host(file, "%-16s: %s\n", proc->name, tmp);
					count += strlen(tmp);
				}
				*length -= count;
				free(*buffer);
				*buffer = (char *)NULL;
				if (*length)
				{
					*buffer = malloc(sizeof(char) * *length);
					memcpy(*buffer, tmp, *length);
				}
			}
			tmp = sep;
		} while (tmp);
	}

	if (flush && proc->status && file == stderr)
	{
		if (proc->watchdog == -1)
			print_host(file, "%-16s: killed by watchdog timer\n", proc->name);
		if (WIFEXITED(proc->status))
			print_host(file, "%-16s: exit %d\n", proc->name, WIFEXITED(proc->status));
		if (WIFSIGNALED(proc->status))
			print_host(file, "%-16s: killed (%d)\n", proc->name, WTERMSIG(proc->status));
		if (WIFSTOPPED(proc->status))
			print_host(file, "%-16s: killed (%d)\n", proc->name, WSTOPSIG(proc->status));


	}

	free(out);
	out = (char *)NULL;

	return count;
}

int
proc_read(int fd, char **buffer, int *length)
{
	char	 readbuf[TMPBUFSIZE];
	int	 count;

	memset(&readbuf, '\0', sizeof(readbuf));

	if ((count = read(fd, &readbuf, sizeof(readbuf))) > 0)
	{
		char *tmp;

		debug_msg("proc_read() got %d bytes\n", count);

		tmp = (char *)malloc(sizeof(char) * (*length + count));
		memset(tmp, '\0', sizeof(char) * (*length + count));
		if (*length)
		{
			memcpy(tmp, *buffer, *length);
			free(*buffer);
			*buffer = (char *)NULL;
		}
		*buffer = tmp;
		memcpy(*buffer + (*length), readbuf, sizeof(char) * count);
		*length += count;
	} else if (count < 0) {
		perror("proc_read() read");
	}

	return count;
}

pid_t
proc_spawn(struct process *proc)
{
	pid_t	 pid;
	int	 stdinpipe[2],
		 stdoutpipe[2],
		 stderrpipe[2];

	if (sigchld == -1)
	{
		signal(SIGCHLD, &proc_sig_child);
		sigchld = 0;
	}

	if ((pipe(stdinpipe) != 0) ||
	    (pipe(stdoutpipe) != 0) ||
	    (pipe(stderrpipe) != 0))
	{
		perror("proc_spawn() pipe");
		exit(1);
	}

	if ((pid = fork()) < 0)
	{
		print_error("fork error!\n");
		exit(1);
	}

	if (pid > 0)
	{
		int fdflags;
		char **tmp = proc->argv;
		/* Parent */
		proc->pstdin = stdinpipe[1];
		close(stdinpipe[0]);
		proc->pstdout = stdoutpipe[0];
		close(stdoutpipe[1]);
		proc->pstderr = stderrpipe[0];
		close(stderrpipe[1]);

		/* set descriptors to non-blocking XXX */
		if (!((fdflags = fcntl(proc->pstdout, F_GETFL, 0)) < 0))
		{
			if ((fcntl(proc->pstdout, F_SETFL, fdflags | O_NDELAY)) < 0)
				perror("proc_spawn() fcntl stdout");
		} else {
			perror("proc_spawn() fcntl stdout");
		}
		if (!((fdflags = fcntl(proc->pstderr, F_GETFL, 0)) < 0))
		{
			if ((fcntl(proc->pstderr, F_SETFL, fdflags | O_NDELAY)) < 0)
				perror("proc_spawn() fcntl stderr");
		} else {
			perror("proc_spawn() fcntl stderr");
		}
		debug_msg("proc_spawn(): ");
		while (*tmp)
			debug_msg("%s ", *tmp++);
		debug_msg("\n");

		return pid;
	} else {
		/* Child */
		
		/*
		 * XXX Convince SSH that I am not going to talk to it, under any circumstances!
		 *      na-na-na-na i'm not talking to you na-na-na-na
		 */
#if defined HAVE_UNSETENV
		unsetenv("DISPLAY");
#elif defined HAVE_PUTENV
		putenv("DISPLAY=");
#endif
		setsid();

		if ((dup2(stdinpipe[0], fileno(stdin)) == -1) ||
		    (dup2(stdoutpipe[1], fileno(stdout)) == -1) ||
		    (dup2(stderrpipe[1], fileno(stderr)) == -1))
		{
			perror("proc_spawn() dup2");
			exit(1);
		}
		/*fclose(stdin);*/
		proc->pstdin = -1;
		close(stdinpipe[0]);
		close(stdinpipe[1]);
		close(stdoutpipe[0]);
		close(stdoutpipe[1]);
		close(stderrpipe[0]);
		close(stderrpipe[1]);

		/* exec sub process XXX */
		execvp(proc->argv[0], proc->argv);

		print_error("dsh: subprocess failed to exec: %s\n", strerror(errno));

		exit(1); /* Failed to exec ! */
	}
}
