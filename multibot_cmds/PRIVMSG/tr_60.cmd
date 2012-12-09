#!/usr/bin/env python
# 60 = `

import sys
import os
import socket
import string
import subprocess
import fcntl

ignored_nicks = ['Lymia', 'Lymee', 'Madoka-Kaname']

help_text = '''\
Runs arbitrary code in GNU/Linux. Type "`<command>", or "`run \
<command>" for full shell commands. "`fetch <URL>" downloads \
files. Files saved to $PWD are persistent, and $PWD/bin is in \
$PATH. $PWD is a mercurial repository, "`revert <rev>" can be used to \
revert to a revision. See http://codu.org/projects/hackbot/fshg/\
'''

irc = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
irc.connect(os.environ['IRC_SOCK'])

message = sys.argv[3][1:]
channel = sys.argv[2]
if not channel.startswith('#'):
    channel = os.environ['IRC_NICK']

def say(text):
    irc.send('PRIVMSG %s :%s\n' % (channel, text))

def calldevnull(*args):
    p = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    p.communicate()

def transact(log, *args):
    lockf = os.open("lock", os.O_RDWR)
    fcntl.flock(lockf, fcntl.LOCK_SH)

    proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = proc.communicate()[0]

    # Check if we wrote
    status = subprocess.Popen(["hg", "status", "-R", os.environ['HACKENV'], "-umad"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    so = status.communicate()[0]
    if so != "":
        # OK, we need to do this exclusively
        fcntl.flock(lockf, fcntl.LOCK_EX)

        status = subprocess.Popen(["hg", "status", "-R", os.environ['HACKENV'], "-umad"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        so = status.communicate()[0]

        # Remove anything broken
        for sline in so.split("\n"):
            if sline == "":
                break
            f = sline.split(" ")[1]
            try:
                os.remove(os.path.join(os.environ['HACKENV'], f))
            except:
                pass

        # Get ourselves back up to date
        calldevnull("hg", "up", "-R", os.environ['HACKENV'], "-C")

        # Run again
        proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        output = proc.communicate()[0]

        # And commit
        if os.path.exists(os.path.join(os.environ['HACKENV'], "canary")):
            calldevnull("hg", "addremove", "-R", os.environ['HACKENV'])
            calldevnull("hg", "commit", "-R", os.environ['HACKENV'], "-m", "<%s> %s" %
                (os.environ['IRC_NICK'], log))

    fcntl.flock(lockf, fcntl.LOCK_UN)
    os.close(lockf)

    output = string.replace(string.rstrip(output), "\n", " \\ ")
    if output == "":
        output = "No output."
    say(output)

parts = message.split(' ', 1)
command = parts[0]
arg = parts[1] if len(parts) > 1 else ''

if any(os.environ['IRC_NICK'].startswith(ignore) for ignore in ignored_nicks):
    say('Mmmmm... no.')
    sys.exit(1)

if command == 'help':
    say(help_text)
elif command == 'fetch':
    transact('fetch ' + arg, 'lib/fetch', arg)
elif command == 'run':
    transact(arg, 'lib/sandbox', 'bash', '-c', arg)
elif command == 'revert':
    transact('revert ' + arg, 'lib/revert', arg)
else:
    if arg:
        transact(command + ' ' + arg, 'lib/sandbox', command, arg)
    else:
        transact(command, 'lib/sandbox', command)
