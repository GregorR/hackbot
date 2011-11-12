#!/bin/bash
# 60 = `

. lib/interp

say() {
    if [ $# -lt 1 ]
    then
        TEXT=$(cat)
    else
        TEXT=$1
    fi
    if [ "$IRC_SOCK" != "" ]
    then
        echo "PRIVMSG $CHANNEL :$TEXT" | socat STDIN UNIX-SENDTO:"$IRC_SOCK"
    else
        echo "$TEXT"
    fi
}

die() {
    say "$1"
    exit 1
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

# Ignore Lymia
echo -n "$IRC_NICK" | grep -c '^Lymia\|^Lymee\|^Madoka-Kaname' >/dev/null &&
    die 'Mmmmm ... no.'

# Now clone the environment
export HACKENV=$(mktemp --directory --tmpdir=$HACKTMP hackenv.XXXXXXXXXX)
trap "cd; rm -rf $HACKENV" 0
hg clone env "$HACKENV" >& /dev/null || die 'Failed to clone the environment!'
cd "$HACKENV" || die 'Failed to enter the environment!'

# Add it to the PATH
export UMLBOX_PATH="/hackenv/bin:/opt/python27/bin:/opt/ghc/bin:/usr/bin:/bin"

# Now run the command
runcmd() {
    (
        export http_proxy='http://127.0.0.1:3128'

        umlbox-nice "$@" | 
            head -c 16384 |
            perl -pe 's/\n/ \\ /g' |
            fmt -w350 |
            sed 's/ \\$//'
        echo ''
    ) | (
        read -r LN
        if [ "$LN" ]; then
            LN=`echo "$LN" | sed 's/[\x01-\x1F]/./g ; s/^\([^a-zA-Z0-9]\)/\xE2\x80\x8B\1/ ; s/\\\\/\\\\\\\\/g'`
            echo -e "$LN" | say
        else
            say 'No output.'
        fi

        # Discard remaining output
        cat > /dev/null
    )
}

(
    # Special commands
    if [ "$CMD" = "help" ]
    then
        say 'Runs arbitrary code in GNU/Linux. Type "`<command>", or "`run <command>" for full shell commands. "`fetch <URL>" downloads files. Files saved to $PWD are persistent, and $PWD/bin is in $PATH. $PWD is a mercurial repository, "`revert <rev>" can be used to revert to a revision. See http://codu.org/projects/hackbot/fshg/'

    elif [ "$CMD" = "fetch" ]
    then
        (
            ulimit -f 10240
            (wget -nv "$ARG" < /dev/null 2>&1 | tr "\n" " "; echo) |
                sed 's/^/PRIVMSG '$CHANNEL' :/' |
                say
        )

    elif [ "$CMD" = "run" ]
    then
        runcmd bash -c "$ARG"

    elif [ "$CMD" = "revert" ]
    then
        if [ "$ARG" = "" ]
        then
            REV=-2
        else
            REV=$ARG
        fi
        OUTPUT=$(hg revert --all -r "$REV" 2>&1)
        if [ $? -eq 0 ]
        then
            say 'Done.'
        else
            say "$OUTPUT"
        fi

    else
        if [ "$ARG" = "" ]
        then
            runcmd "$CMD"
        else
            runcmd "$CMD" "$ARG"
        fi
    fi

    # Now commit the changes (make multiple attempts in case things fail)
    if [ ! -e canary ] ; then exit 1 ; fi
    for (( i = 0; $i < 10; i++ ))
    do
        find . -name '*.orig' | xargs rm -f
        hg addremove >& /dev/null || die "Failed to record changes."
        hg commit -m "<$IRC_NICK> $CMD $ARG" >& /dev/null || 
        hg commit -m "<$IRC_NICK> (unknown command)" >& /dev/null ||
        hg commit -m "No message" #|| die "Failed to record changes."
    
        hg push >& /dev/null && break || (
            # Failed to push, that means we need to pull and merge
            hg pull >& /dev/null
            for h in `hg heads --template='{node} ' 2> /dev/null`
            do
                hg merge $h >& /dev/null
                hg commit -m 'branch merge' >& /dev/null
                hg revert --all >& /dev/null
                find . -name '*.orig' 2> /dev/null | xargs rm -f >& /dev/null
            done
        )
    done
) &

sleep 30
kill -9 %1
