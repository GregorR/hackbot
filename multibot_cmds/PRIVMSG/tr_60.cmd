#!/usr/bin/env python
# 60 = `

import sys
import os
import socket

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

server = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
server.connect(os.environ['SERVER_SOCK'])

message = sys.argv[3][1:]
channel = sys.argv[2]
if not channel.startswith('#'):
    channel = os.environ['IRC_NICK']

def say(text):
    irc.send('PRIVMSG %s :%s\r\n' % (channel, text))

def transact(*args):
    data = [os.environ['IRC_SOCK'], os.environ['IRC_NICK'], channel]
    data += list(args)
    server.send(chr(len(data)) + data)

parts = message.split(' ', 1)
command = parts[0]
arg = parts[1] if len(parts) > 1 else None

if any(os.environ['IRC_NICK'].startswith(ignore) for ignore in ignored_nicks):
    say('Mmmmm ... no.')
    sys.exit(1)

if command == 'help':
    say(help_text)
elif command == 'fetch':
    transact('lib/fetch', arg)
elif command == 'run':
    transact('lib/sandbox', 'bash', '-c', arg)
elif command == 'revert':
    transact('lib/revert', arg)
else:
    if arg:
        transact('lib/sandbox', command, arg)
    else:
        transact('lib/sandbox', command)
