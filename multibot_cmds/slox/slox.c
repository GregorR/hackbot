/*
 * Copyright (c) 2006  Gregor Richards
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

void chldDied(int, siginfo_t *, void *);

int main(int argc, char **argv)
{
    int pspeed, psi;
    pid_t pid = 0;
    int i;
    
    if (argc < 3) {
        fprintf(stderr, "Use: slox <%%speed> <command|-p pid>\n");
        return 1;
    }
    
    pspeed = (int) (atof(argv[1]) * 100.0);
    if (pspeed <= 0 || pspeed >= 10000) {
        fprintf(stderr, "Speed must be between 1.00 and 99.99 percent.\n");
        return 1;
    }
    
    /* put the pspeed into a reasonable range */
    if (pspeed < 10) {
        pspeed *= 2000;
        psi = 20000000 - pspeed;
    } else if (pspeed < 100) {
        pspeed *= 200;
        psi = 2000000 - pspeed;
    } else if (pspeed < 1000) {
        pspeed *= 20;
        psi = 200000 - pspeed;
    } else {
        pspeed *= 2;
        psi = 20000 - pspeed;
    }
    
    /* parse arguments */
    for (i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "-p")) {
            i++;
            if (i >= argc) {
                fprintf(stderr, "-p needs an argument\n");
                return 1;
            }
            pid = atoi(argv[i]);
        } else break;
    }
    
    /* set a signal for when the child dies */
    struct sigaction sa;
    sa.sa_handler = NULL;
    sa.sa_sigaction = chldDied;
    memset(&(sa.sa_mask), 0, sizeof(sa.sa_mask));
    sa.sa_flags = SA_NOCLDSTOP;
    sigaction(SIGCHLD, &sa, NULL);
    
    /* do we need to fork? */
    if (!pid) {
        pid = fork();
        if (pid == 0) {
            /* sub-program, run it */
            setpgrp();
            execvp(argv[2], argv + 2);
            fprintf(stderr, "Couldn't fork sub-program.\n");
            return 1;
        } else if (pid == -1) {
            perror("fork");
            return 1;
        }
        pid = -pid;
    }
    
    /* then run the loop */
    while (1) {
        usleep(pspeed);
        kill(pid, SIGSTOP);
        usleep(psi);
        kill(pid, SIGCONT);
    }
    
    return 0;
}

void chldDied(int i1, siginfo_t *i2, void *i3)
{
    fflush(stdout);
    exit(0);
}
