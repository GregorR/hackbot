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
        ulimit -v $(( 128 * 1024 ))
        ulimit -t 30
        ulimit -u 1024
    
        echo "$CMD" | pola-nice bash
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
    runcmd

    # Now commit the changes (make multiple attempts in case things fail)
    for (( i = 0; $i < 10; i++ ))
    do
        find . -name '*.orig' | xargs rm -f
        hg addremove || die "Failed to record changes."
        hg commit -m "$CMD" || die "Failed to record changes."
    
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
