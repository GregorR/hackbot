#!/bin/bash
# 3F = ?
CMD=`echo "$3" | sed 's/^.//'`
./PRIVMSG/tr_60.cmd "$1" "$2" '`? '"$CMD"
