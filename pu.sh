#!/bin/sh
#
# Copyright (C) 2008, 2009 Guilherme Gondim <semente@taurinus.org>
#
# pu.sh is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# pu.sh is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
# License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; see the file COPYING.  If not, see
# <http://www.gnu.org/licenses/>.
#
# See <http://pu-sh.googlecode.com/> for updates, bug reports, and answers.
#

VERSION="0.1-pre"


CUT_CMD="`which cut`"           # cut binary
GREP_CMD="`which grep`"         # grep binary

SSH_CMD="`which ssh`"           # OpenSSH client binary
SSH_ARGS="-o Compression=no -x" # ssh arguments

RSYNC_CMD="`which rsync`"       # rsync binary
RSYNC_ARGS="-azH --numeric-ids --relative --delete --delete-excluded"

LOCK_FILE="/tmp/.push$(id -u)-lock" # lock file


# Current point-in-time (pit). Format: YYYY-MM-DD_HH:MM:SS.
# Into DEST directory, pu.sh creates a snapshot with this name format.
PIT="`date +%Y-%m-%d_%H:%M:%S`"

# info for log and other messages
PID=$$
SCRIPT_NAME=`basename $0`
DATE_FORMAT="%F %T"
LOG_FILE=/dev/null              # no log by default
STD_OUT=/dev/stdout
STD_ERR=/dev/stderr



Log()
{
    LOG_MSG=$@
    LOG_DATE=`date +"$DATE_FORMAT"`
    echo "$LOG_DATE [$PID] ${SCRIPT_NAME}: $LOG_MSG" >> "$LOG_FILE"
}

Print()
{
    Log "$@"
    echo "$@" > $STD_OUT
}

Alert()
{
    Log "(WARN) $@"
    echo "$@" > $STD_ERR
}

Fail()
{
    Log "(ERROR) $@"
    echo "$SCRIPT_NAME: $@" > $STD_ERR
    Log "session finished with errors."
    exit 1
}


Version()
{
    echo "pu.sh  version $VERSION"
    echo "Copyright (C) 2008, 2009 by Guilherme Gondim <semente@taurinus.org>"
    echo
    echo "pu.sh comes with ABSOLUTELY NO WARRANTY.  This is free software, and"
    echo "you are welcome to redistribute it under certain conditions.  See the"
    echo "GNU General Public Licence version 3 for details."
}

Usage()
{
    echo "Usage: $SCRIPT_NAME [-q] [-v]... [-e FILE] [-l FILE] [--] SRC [SRC]... [[USER@]HOST:]DEST"
    echo "Try \`$0 -h' for more information."
}

Help()
{
    Version
    echo
    echo "Usage: $SCRIPT_NAME [OPTION]... [--] SRC [SRC]... [[USER@]HOST:]DEST"
    echo "Push a snapshot from SRC(s) to DEST in local or remote host."
    echo
    echo " Examples:"
    echo
    echo "  pu.sh /root /home /usr/local/bin /var/backups"
    echo "  pu.sh -e exclude.list / root@example.net:/backups/$HOSTNAME"
    echo "  pu.sh -l /var/log/pu-sh.log /var/mail root@192.168.0.1:/var/cache/pu-sh"
    echo
    echo " Options:"
    echo
    echo "  -e EXCLUDE-FILE         File with exclude patterns (rsync syntax)."
    echo "                          Specify \"-\" for standard input."
    echo "  -l LOG-FILE             file to write log"
    echo "  -q                      suppress non-error messages"
    echo "  -v                      increase verbosity"
    echo "  -V                      print version number"
    echo "  -h                      this help!"
    echo
    echo "See <http://pu-sh.googlecode.com/> for updates, bug reports, and answers."
}


ParseCommandLine()
{
    while getopts hvVql:e: OPT; do
        case $OPT in
            e)                  # exclude list
                RSYNC_ARGS="$RSYNC_ARGS --exclude-from='$OPTARG'"
                ;;
            l)                  # log
                LOG_FILE="$OPTARG"
                RSYNC_LOG_FORMAT="rsync: %o %f %l"
                RSYNC_ARGS="$RSYNC_ARGS --log-file='$LOG_FILE' --log-file-format='$RSYNC_LOG_FORMAT'"
                ;;
            q)                  # suppress non-error messages
                STD_OUT=/dev/null
                ;;
            v)                          # increase verbosity
                RSYNC_ARGS="--verbose $RSYNC_ARGS"
                ;;
            V)                  # print version
                Version
                exit
                ;;
            h)                  # print help
                Help
                exit
                ;;
            *)                  # invalid option
                Usage
                exit 2
        esac
    done
    shift `expr $OPTIND - 1`

    ARGNUM=$#
    ARGIND=1

    if [ $ARGNUM -lt 2 ]; then
        echo "$SCRIPT_NAME: missing arguments!"
        Usage
        exit 2
    fi

    SOURCES=""
    for ARG in "$@"; do                 # the quotes are important
        if [ $ARGIND -eq $ARGNUM ]; then # last argument
            # last argument is the target in format `[[USER@]HOST:]DEST'
            TARGET=$ARG
        else
            SOURCES="$SOURCES '$ARG'"
            ARGIND=`expr $ARGIND + 1`
        fi
    done

    # check if `$TARGET' have a form `[[USER@]HOST:]DEST'
    USER_RE="[a-z0-9A-Z][-a-z0-9A-Z_]*"
    HOST_RE="[-a-z0-9A-Z_.]+"
    DEST_RE="[-a-z0-9A-Z_/.~]+"

    echo $TARGET | $GREP_CMD -E "^${DEST_RE}\$" > /dev/null
    if [ $? -eq 0 ]; then
        DEST=$TARGET
        USE_SSH=0               # backup in local host

        # excludes directory destination when performing a backup local
        RSYNC_ARGS="$RSYNC_ARGS --exclude=$DEST"
    else
        echo $TARGET | $GREP_CMD -E \
            "^((${USER_RE}@)?${HOST_RE}:)?${DEST_RE}\$" > /dev/null
        if [ $? -gt 0 ]; then
            echo "$SCRIPT_NAME: invalid destination $TARGET"
            Usage
            exit 2
        fi

        HOST=`echo $TARGET | $CUT_CMD -d: -f1` # get [USER@]HOST part
        DEST=`echo $TARGET | $CUT_CMD -d: -f2` # get destination directory

        # backup in remote host
        USE_SSH=1
        RSYNC_ARGS="-e '$SSH_CMD $SSH_ARGS' $RSYNC_ARGS"
    fi
}

CreateLockFile()
{
    echo $PID > "$LOCK_FILE" && chmod 444 "$LOCK_FILE"
    return $?
}

DeleteLockFile() { rm -f "$LOCK_FILE" ; }

MakeSnapshotDir()
{
    ## Creates the directory in remote or local host where we push the snapshot.

    if [ $USE_SSH -eq 1 ]; then
        $SSH_CMD $HOST mkdir -p $DEST/$PIT
    else
        mkdir -p $DEST/$PIT
    fi

    return $?
}

CheckPreviousSnapshot()
{
    ## Checks if we have a previous snapshot for use rsync's hardlinking
    ## capability.

    HAVE_PREVIOUS=0
    if [ $USE_SSH -eq 1 ]; then
        $SSH_CMD $HOST test -L $DEST/last
    else
        test -L $DEST/last
    fi
    test $? -eq 0 && HAVE_PREVIOUS=1
}

UpdateSymlinkLast()
{
    ## Update the symlink `last'.

    if [ $USE_SSH -eq 1 ]; then
        $SSH_CMD $HOST ln -snf $DEST/$PIT $DEST/last
    else
        ln -snf $DEST/$PIT $DEST/last
    fi

    return $?
}

PushSnapshot()
{
    ## Push a snapshot to `[[USER@]HOST:]DEST'. If we have a previous snapshot
    ## in DEST directory, we uses the rsync's hardlinking capability for create
    ## a new snapshot without data redundancy.

    if [ $HAVE_PREVIOUS -eq 1 ]; then
        # We have a previous snapshot, using rsync's hardlinking capability
        # based on symlink `last' found in destination directory.
        RSYNC_ARGS="$RSYNC_ARGS --link-dest='../last'"
    fi

    Log "using these rsync arguments: \"$RSYNC_ARGS\""

    eval "$RSYNC_CMD $RSYNC_ARGS $SOURCES ${HOST:+$HOST:}$DEST/$PIT"

    return $?
}

Main()
{
    ParseCommandLine "$@"

    trap "Print KILLED; exit 1" 1 2 3 15

    Log "session started -- version $VERSION"

    if [ -e "$LOCK_FILE" ]; then
        Fail "other pu.sh process in execution -- ABORTED!"
    else
        trap "DeleteLockFile" 0
        trap "DeleteLockFile; Print KILLED; exit 1" 1 2 3 15
        CreateLockFile || Fail "cannot create lock file -- ABORTED!"
    fi

    Log "lock file is \`$LOCK_FILE'."

    test -z $CUT_CMD && \
        Fail "you need \`cut' installed in your PATH  -- ABORTED!"
    test -z $GREP_CMD && \
        Fail "you need \`grep' installed in your PATH  -- ABORTED!"
    test -z $RSYNC_CMD && \
        Fail "you need \`rsync' installed in your PATH -- ABORTED!"
    test $USE_SSH -eq 1 -a -z $SSH_CMD && \
        Fail "you need OpenSSH client installed in your PATH -- ABORTED!"

    Log "the sources are $SOURCES."
    Log "the destination is \`${HOST:+$HOST:}$DEST'."

    CheckPreviousSnapshot
    if [ $HAVE_PREVIOUS -eq 1 ]; then
        Log "previous snapshot found, using rsync's hardlinking capability."
    else
        Log "no previous snapshot for this destination, the first will be created."
    fi

    MakeSnapshotDir || Fail "fail when make remote directory for snapshot -- ABORTED!"
    Log "directory \`${HOST:+$HOST:}$DEST/$PIT' for snapshot created."

    PushSnapshot || Fail "fail when push snapshot -- ABORTED!"

    UpdateSymlinkLast || Alert "cannot update the symlinst \`last'."

    Log "session done."
}

Main "$@"
