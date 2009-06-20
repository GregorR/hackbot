#!/bin/bash
# 60 = `

. lib/dcc
. lib/interp

# Undo commands stored here
export UNDO="true"

die() {
    bash -c "$UNDO"
    if [ "$IRC_SOCK" != "" ]
    then
        echo "$1" | socat STDIN UNIX-SENDTO:"$IRC_SOCK"
    else
        echo "$1"
    fi
    exit 1
}

undo() {
    export UNDO="$UNDO; $1"
}

maybe_dcc_chat() {
    if [ "$IRC_SOCK" != "" ]
    then
        dcc_chat "$@"
    else
        cat
    fi
}

if [ "$IRC_SOCK" != "" ]
then
    CMD=`echo "$3" | sed 's/^.//'`
    CHANNEL="$2"
    if ! expr "$CHANNEL" : "#" > /dev/null
    then
        CHANNEL="$IRC_NICK"
    fi
else
    CMD="$1"
fi
SCMD=`echo "$CMD" | sed 's/^\([^ ]*\) .*$/\1/'`
ARG=`echo "$CMD" | sed 's/^\([^ ]*\) *//'`
CMD="$SCMD"

# Now clone the environment
hg clone env /tmp/hackenv.$$ || die "Failed to clone the environment!"
undo "cd; rm -rf /tmp/hackenv.$$"
cd /tmp/hackenv.$$ || die "Failed to enter the environment!"

# Add it to the PATH
export PATH="/tmp/hackenv.$$/bin:/usr/bin:/bin"

# Now run the command
runcmd() {
    (
        ulimit -f 10240
        ulimit -l 0
        ulimit -v $(( 128 * 1024 ))
        ulimit -t 30
        ulimit -u 128
    
        pola-nice "$@" | 
            head -c 16384 |
            perl -pe 's/\n/ \\ /g' |
            fmt -w350 |
            sed 's/ \\$//'
        echo ''
    ) | (
        if [ "$IRC_SOCK" != "" ]
        then
            read -r LN
            if [ "$LN" ]; then
                echo 'PRIVMSG '$CHANNEL' :'"$LN" | socat STDIN UNIX-SENDTO:"$IRC_SOCK"
            fi
        
            LN=
            while read -r LN
            do
                if [ "$LN" != "" ] ; then break ; fi
            done
        
            if [ "$LN" != "" ]
            then
                # OK, send the rest over DCC
                (
                    echo "$LN"
                    cat | head -c 16384
                ) | dcc_chat "$IRC_NICK"
            fi
    
        else
            cat
        fi
    )
}

(
    # Special commands
    if [ "$CMD" = "help" ]
    then
        echo 'PRIVMSG '$CHANNEL' :This is HackBot, the extremely hackable bot. To run a command with one argument, type "`<command>", or "`run <command>" to run a shell command. "`fetch <URL>" downloads files, otherwise the network is inaccessible. Files saved to $PWD are persistent, and $PWD/bin is in $PATH. $PWD is a mercurial repository; if you'\''re faimilar with mercurial, you can fix any problems caused by accidents or malice.' |
            socat STDIN UNIX-SENDTO:"$IRC_SOCK"

    elif [ "$CMD" = "fetch" ]
    then
        (
            ulimit -f 10240
            (wget -nv "$ARG" < /dev/null 2>&1 | tr "\n" " "; echo) |
                sed 's/^/PRIVMSG '$CHANNEL' :/' |
                socat STDIN UNIX-SENDTO:"$IRC_SOCK"
        )

    elif [ "$CMD" = "run" ]
    then
        echo "$ARG" | runcmd bash
    else
        if [ "$ARG" = "" ]
        then
            runcmd "$CMD"
        else
            runcmd "$CMD" "$ARG"
        fi
    fi

    # Now commit the changes (make multiple attempts in case things fail)
    for (( i = 0; $i < 10; i++ ))
    do
        find . -name '*.orig' | xargs rm -f
        hg addremove || die "Failed to record changes."
        hg commit -m "$CMD $ARG" || die "Failed to record changes."
    
        hg push && break || (
            # Failed to push, that means we need to pull and merge
            hg pull
            for h in `hg heads --template='{node} '`
            do
                hg merge $h
                hg commit -m 'branch merge'
                hg revert --all
                find . -name '*.orig' | xargs rm -f
            done
        )
    done
) &

sleep 30
kill -9 %1

# And get rid of our tempdir
bash -c "$UNDO"
