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
 * $Id: dsh.c,v 1.25 2005/10/18 01:20:45 lile Exp $
 */

#include "includes.h"

RCSID("$Id: dsh.c,v 1.25 2005/10/18 01:20:45 lile Exp $");

#if !defined(RSH_DFLT)
#define RSH_DFLT "/usr/bin/rsh"
#endif /* !defined RSH_DFLT */

#if !defined(SSH_DFLT)
#define SSH_DFLT "/usr/bin/ssh"
#endif /* !defined SSH_DFLT */

#if !defined(DSHPATH_DFLT)
#define DSHPATH_DFLT "/usr/ucb:/bin:/usr/bin:."
#endif /* !defined DSHPATH_DFLT */

#define MAX_FANOUT(x)	((x - 3) / 3)
#define TIMEOUT		180

unsigned int	 qflag = 0,
		 iflag = 0,
		 vflag = 0,
		 cflag = 0,
		 tflag = 1, /* XXX Default shell from configure */
		 dflag = 0,
		 Dflag = 0,
		 fflag = 64;

char		*lflag = (char *)NULL,
		*wflag = (char *)NULL,
		*oflag = (char *)NULL,
		*Yflag = (char *)NULL;

int		 signaled = 0,
		 sigcount = 0;

unsigned int	 collate = 0;

extern int 	 errno;

char		*__ypdomain = NULL;

char		**remote_argv = (char **)NULL,
		 *remote_host = (char *)NULL,
		**remote_cmdv = (char **)NULL;
int		  remote_argc = 0;

void
push_remote_argv(char *argument)
{
	char **tmp;

	/* +2 because we keep the remote_argv null terminated  */
	if ((tmp = (char **)malloc(sizeof(char *) * (remote_argc + 2))) == NULL)
	{
		perror("Unable to allocate remote arguments - malloc");
		exit(1);
	}
	memset(tmp, '\0', sizeof(char *) * (remote_argc + 2));

	if (remote_argv)
	{
		memcpy(tmp, remote_argv, remote_argc * sizeof(char *));
		free(remote_argv);
	}
	remote_argv = tmp;

	if (argument)
		remote_argv[remote_argc] = strdup(argument);

	remote_argc++;
}

void
sig_handler(int signum)
{
	debug_msg("sig_handler(%d)\n", signum);
	signaled = signum;
	sigcount++;
	if (sigcount > 5)
	{
		print_error("Something must be hung, exiting...\n");
		exit(1);
	}
}

char *
clean_string(char *string)
{
	char	*s = string,
		*t;

	while (s && isspace(*s))
		s++;

	if (*s == '#')
		return (char *)NULL;

	if (!s)
		return s;

	t = s + strlen(s) - 1;
	while (t > s && isspace(*t))
		t--;
	*++t = '\0';

	return s;
}

int
execute_command(int quiet, char *hn_method, int timeout, int argc, char **argv)
{
	int		 rc = 0;
	struct member	*ptr;
	int		 watchdog = timeout,
			 watchdogs_set = 0,
			 queue_watchdog = 0;

	signaled = 0;
	sigcount = 0;

	if (iflag)
	{
		char **cmdp = remote_cmdv;
		collective_display();
		printf("command: ");
		while(*cmdp)
			printf("%s ", *cmdp++);
		printf("\n");
	}

	queue_max_slots(fflag);
	ptr = collective_get_next(NULL);
	while (((ptr && !signaled) || queue_load()))
	{
		time_t now = time(NULL);
		if (queue_slots() == 0)
		{
			if (watchdog > now)
			{
				debug_msg("queue watchdog expired\n");
				queue_set_watchdogs(watchdog);
				watchdogs_set = 1;
			}
			if (!watchdog)
			{
				debug_msg("setting watchdog on queue\n");
				queue_watchdog = now + watchdog;
			}
		}
		if (queue_slots() && queue_watchdog)
		{
			debug_msg("clearing watchdog on queue\n");
			queue_watchdog = 0;
		}

		while (queue_slots() > 0 && (!signaled && ptr))
		{
			struct member	*next;
			next = collective_get_next(ptr);
			if (cflag || ptr->responding)
			{
				char *name = ptr->name;
				if (!strcmp(hn_method, "reliable"))
					name = ptr->reliable;
				queue_insert(ptr, name, argc, argv);
			} else {
				debug_msg("%s not responding, dropped from collective\n",
						ptr->name);
				collective_drop_member(ptr);
			}
			ptr = next;
		}
		rc += queue_run(quiet, signaled);

		if (!ptr && queue_load() && !watchdogs_set)
		{
			queue_set_watchdogs(watchdog);
			watchdogs_set = 1;
		}
	}

	if (signaled > 0 && queue_load() > 0)
	{
		debug_msg("queued processes to be killed: %d\n",
		    queue_load());
	}

	return rc;
}

int
main(int argc, char **argv)
{
	int		 ch,
			 i,
			 dshtimeout = TIMEOUT;
	char		*wcoll = (char *)NULL,
			*fanout,
			*dsh_remote_cmd = RSH_DFLT,
			*rcmd_pgm = "rsh",
			*hn_method = (char *)NULL,
			*dshpath = (char *)NULL,
			*prompt,
			*envp;

	char		*ping[] = { "ping", "-w", "4", NULL, NULL };

#if defined(RLIMIT_NOFILE) || defined(RLIMIT_NPROC)
	struct rlimit	 rl;
#endif /* defined(RLIMIT_NOFILE) || defined(RLIMIT_NPROC) */

	int		 rc = 0;

	if (geteuid() == 0)
		prompt = "dsh# ";
	else
		prompt = "dsh> ";

	if (getenv("DSH_DEBUG") != NULL)
		set_debug(1);
	debug_msg("DSH_DEBUG\n");

	rcmd_pgm = (envp = getenv("RCMD_PGM")) ? envp : "rsh";
	if (!strcmp(rcmd_pgm, "rsh"))
		dsh_remote_cmd = (envp = getenv("DSH_REMOTE_CMD")) ? envp : RSH_DFLT;
	else if (!strcmp(rcmd_pgm, "secrshell"))
		dsh_remote_cmd = (envp = getenv("DSH_REMOTE_CMD")) ? envp : SSH_DFLT;
	else
	{
		print_error("unknown RCMD_PGM %s\n", rcmd_pgm);
		exit(1);
	}
	debug_msg("DSH_REMOTE_CMD = %s\n", dsh_remote_cmd);
	debug_msg("RCMD_PGM = %s\n", rcmd_pgm);

	push_remote_argv(dsh_remote_cmd);

	hn_method = (envp = getenv("HN_METHOD")) ? envp : "initial_hostname";
	if (strcmp(hn_method, "initial_hostname") &&
	    strcmp(hn_method, "reliable"))
	{
		print_error("unknown HN_METHOD %s\n", hn_method);
		exit(1);
	}
	debug_msg("HN_METHOD = %s\n", hn_method);

	dshpath = (envp = getenv("DSHPATH")) ? envp : DSHPATH_DFLT;
	debug_msg("DSHPATH = %s\n", dshpath);

	if (getenv("DSH_TIMEOUT"))
		dshtimeout = atoi(getenv("DSH_TIMEOUT"));
	debug_msg("DSH_TIMEOUT = %d\n", dshtimeout);

	if (getenv("DSH_COLLATE") != NULL)
	{
		collate = 1;
		debug_msg("DSH_COLLATE\n");
	}

#if defined(RLIMIT_NOFILE)
	if (getrlimit(RLIMIT_NOFILE, &rl) == -1)
	{
		perror("getrlimit");
	} else {
		debug_msg("RLIMIT_NOFILE = %d (%d)\n",
		    rl.rlim_cur, rl.rlim_max);
		debug_msg("maximum fanout: %d\n", MAX_FANOUT(rl.rlim_cur));
		/* XXX Reduce fflag if necessary */
	}
#endif /* defined(RLIMIT_NOFILE) */

#if defined(RLIMIT_NPROC)
	if (getrlimit(RLIMIT_NPROC, &rl) == -1)
	{
		perror("getrlimit");
	} else {
		debug_msg("RLIMIT_NPROC = %d (%d)\n",
		    rl.rlim_cur, rl.rlim_max);
		/* XXX Reduce fflag if necessary */
	}
#endif /* defined(RLIMIT_NPROC) */

	if ((fanout = getenv("FANOUT")) != NULL && atoi(fanout) > 0)
		fflag = atoi(fanout);

	while ((ch = getopt(argc, argv, "qhivct:dDl:w:f:o:")) != -1)
	{
		switch(ch)
		{
			case 'q':
				qflag = 1;
				break;
			case 'h':
				exit(usage(argv[0]));
				break;
			case 'i':
				iflag = 1;
				break;
			case 'v':
				vflag = 1;
				break;
			case 'c':
				cflag = 1;
				break;
			case 't':
				if (!strcmp(optarg, "sh") || !strcmp(optarg, "ksh"))
					tflag = 0;
				else if (!strcmp(optarg, "csh") || !strcmp(optarg, "tcsh"))
					tflag = 1;
				else
				{
					print_error("%s unknown shell syntax.\n", optarg);
					exit(1);
				}
				break;
			case 'd':
				dflag = 1;
				if (Dflag)
				{
					print_error("-D and -d cannot be used at the same time.\n");
					exit(1);
				}
				break;
			case 'D':
				Dflag = 1;
				if (dflag)
				{
					print_error("-D and -d cannot be used at the same time.\n");
					exit(1);
				}
				break;
			case 'l':
				lflag = strdup(optarg);
				break;
			case 'w':
				wflag = strdup(optarg);
				break;
			case 'f':
				fflag = atoi(optarg);
				break;
			case 'o':
				oflag = strdup(optarg);
				push_remote_argv(oflag);
				break;
			case 'Y':
				Yflag = strdup(optarg);
				__ypdomain = Yflag;
				break;
			default:
				exit(!usage(argv[0]));
				break;
		}
	}

	argc -= optind;
	argv += optind;

	if (lflag)
	{
		push_remote_argv("-l");
		push_remote_argv(lflag);
	}
	if (dflag)
		push_remote_argv("-f");
	if (Dflag)
		push_remote_argv("-F");

 	/* XXX First NULL argument becomes hostname */
	remote_host = remote_argv[remote_argc];
	push_remote_argv(NULL);

	if (strlen(dshpath))
	{
		char *tmp;
		if (tflag)
		{
			tmp = (char *)malloc(sizeof(char) *
				(strlen(dshpath) + strlen("setenv PATH ;") + 1) );
			sprintf(tmp, "setenv PATH %s;", dshpath);
		} else {
			tmp = (char *)malloc(sizeof(char) *
				(strlen(dshpath) + strlen("PATH=; export PATH;") + 1) );
			sprintf(tmp, "PATH=%s; export PATH;", dshpath);
		}
		push_remote_argv(tmp);
		free(tmp);
	}

	if (argc)
		for (i = 0; i < argc; i++)
			push_remote_argv(argv[i]);
	remote_cmdv = &remote_argv[remote_argc - argc];

	debug_msg("remote_argv = ");
	for (i = 0; i < remote_argc; i++)
		debug_msg("%s ", (remote_argv[i] ? remote_argv[i] : "(NULL)"));

	debug_msg("\nremote_argc = %d\n", remote_argc);
	
	if (!wflag && ((wcoll = getenv("WCOLL")) == NULL))
	{
		print_error("working collective not set.\n");
		exit(1);
	}

	if (wflag)
	{
		if (*wflag != '-')
		{
			debug_msg("loading collective from -w\n");
			collective_parse(wflag, ',');
		} else {
			debug_msg("loading collective from stdin\n");
			collective_add_stdin(stdin);
		}
	} else {
		FILE	*file = stdin;
		debug_msg("loading collective from WCOLL=%s\n", wcoll);
		if ((file = fopen(wcoll, "r")) == NULL)
		{
			perror("fopen");
			return 1;
		}
		collective_add_file(file);
	}

	if (qflag)
		return collective_display();

	signal(SIGINT,  &sig_handler);
	signal(SIGQUIT, &sig_handler);
	signal(SIGABRT, &sig_handler);

	if (vflag)
	{
		execute_command(1, hn_method, 10, 4, ping);
	}

	if (argc == 0)
	{
#if defined(HAVE_READLINE)
		char *line;
		while (1)
		{
			char *s;

			signal(SIGINT,  SIG_DFL);
			signal(SIGQUIT, SIG_DFL);
			signal(SIGABRT, SIG_DFL);
			
			if ((line = readline(prompt)) == NULL)
				break;

			if ((s = clean_string(line)) == NULL)
				continue;

			signal(SIGINT,  &sig_handler);
			signal(SIGQUIT, &sig_handler);
			signal(SIGABRT, &sig_handler);
			
			if (s && strlen(s))
			{
				if (!strcmp(s, "exit"))
					break;
#if defined(HAVE_ADD_HISTORY)
				add_history(s);
#endif /* HAVE_ADD_HISTORY */
				if (*s == '!')
				{
					printf("local command: %s\n", s);
					continue;
				} else {
					remote_argv[remote_argc - 1] = strdup(s);
					rc = execute_command(0, hn_method, dshtimeout,
							remote_argc, remote_argv);
				}
			}
		}
		if (line == (char *)NULL)
			printf("\n");
#else
		printf("readline not availble\n");
#endif /* HAVE_READLINE */
	} else {
		rc = execute_command(0, hn_method, dshtimeout, remote_argc, remote_argv);
	}

	signal(SIGINT,  SIG_DFL);
	signal(SIGQUIT, SIG_DFL);
	signal(SIGABRT, SIG_DFL);

	for (i = 0; i < remote_argc; i++)
		if (remote_argv[i])
		{
			free(remote_argv[i]);
			remote_argv[i] = (char *)NULL;
		}
	free(remote_argv);
	remote_argv = (char **)NULL;

	free_collective();

	if (lflag)
	{
		free(lflag);
		lflag = (char *)NULL;
	}
	if (wflag)
	{
		free(wflag);
		wflag = (char *)NULL;
	}
	if (oflag)
	{
		free(oflag);
		oflag = (char *)NULL;
	}
	if (Yflag)
	{
		free(Yflag);
		Yflag = (char *)NULL;
	}

	return rc;
}
