#!/bin/sh
# This is an EXAMPLE runner script. You should make your own.
NAME="HackBot"
CHANNEL="hackbot"

cd "`dirname $0`"
if [ ! -e multibot_cmds/env ]
then
    hg init multibot_cmds/env
    touch multibot_cmds/env/canary
    hg addremove -R multibot_cmds/env
    hg commit -R multibot_cmds/env -m 'Adding canary'
fi

while true
do
    socat TCP4:irc.freenode.net:6667 EXEC:'./multibot '"$NAME"' '"$CHANNEL"' '"$NAME"'.log'
done
