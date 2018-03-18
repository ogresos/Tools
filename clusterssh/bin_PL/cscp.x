#!/bin/sh

#LICENSE: GNU GPL version 2
#Author: JT Moree: moreejt@pcxperience.com
#Copyright:  Kahala Corp. 2006
#Date: 20061213
#
# $URL$
# $Id$
#

VERSION='$Revision$ ($Date$)'
PROGRAM=`basename $0`
DEBUG=n
ETC=/etc/clusterscp
CONF=/etc/clusters
RC=/etc/clusterscprc
GRP=
COMMENT=
DEST=
SYSLOG=0

usage()
{
  cat <<FOO

  $PROGRAM v. $VERSION
    Usage: $PROGRAM [options] -C<cluster> file1 file2 file3 . . .
        or $PROGRAM [options] -H<user@host> file1 file2 file3 . . .

This program copies files to multiple remote machines using ssh and scp and can log the action.

LICENSE
  Released under the terms of the GNU GPL version 2

OPTIONS
  -C  server cluster(s) to scp to.  see GROUPS/CLUSTERS
  -D  destination directory on target servers
  -d  Debug mode
  -H  scp to this one host (format user@host)
  -h  help
  -f  Use this config file for groups/clusters.  Use this to override the use of clusterssh config in /etc/clusters.
  -t  comment to describe the action

Make sure to use quotes when there are spaces in your params.

GROUPS/CLUSTERS

This script uses scp to copy files to the specified destination of each server
in a server cluster.  A server cluster is specified in a file (usually $CONF)
in the format:
  <clustername> <user>@<server> <user>@<server> . . . .
See clusterssh for more info

Each cluster may also have custom configurations specified in a file ending with .cfg.
 ie.  servers A, B, and C are in group FOO.  There is a line in file $CONF
   FOO root@A root@B root@C
and potentially another file $ETC/FOO.cfg

CONFIG FILES

In the .cfg file vars can be set in the form of bash/sh vars:
  LOG=/root/Documentation/changelog

LOGGING to SYSLOG

The log string will use the format
  20060111 11:11:11 user clusterscp:cluster:comment: <files>
The script attempts to use logger (syslog) on each target machine.  To turn
this off set the SYSLOG=0 config in $RC or in the .cfg for that cluster.

LOGGING to a CUSTOM LOG

The log string will use the format
  20060111 11:11:11 user clusterscp:group:comment: <files>
The .cfg file can have a parameter set LOG=/path/to/log.  If so, it logs the
action to that file by appending to the end of it.

SSH w/o PASSWORDS

If ssh public/private key authentication is setup with no passphrase then no password is neccessary to scp the files.  Otherwise you will be prompted for each server password.

FOO
}

copy_files()
{
  copy_files_TARGET=$1
  copy_files_DEST=$2
  shift 2
  CHECK=`echo $copy_files_TARGET | grep '@'`
  if [ -z "$CHECK" ] ; then  #target does not have format of user@host.  perhaps it is another cluster?
    #check to see if a cluster matches this name and process it
    copy_cluster "$copy_files_TARGET" "$copy_files_DEST" $@
  else
    if [ "$DEBUG" = "y" ] ; then
      echo scp $@ $copy_files_TARGET:$copy_files_DEST >/dev/null
    else
      scp $@ $copy_files_TARGET:$copy_files_DEST >/dev/null
    fi
    if [ "$?" -eq 0 ] ; then
      echo "$copy_files_TARGET: OK"

      if [ $SYSLOG -eq 1 ] ; then
        if [ "$DEBUG" = "y" ] ; then
          echo ssh $copy_files_TARGET "logger -t$PROGRAM -pauth.info '$LOGSTRING'"
        else
          ssh $copy_files_TARGET "logger -t$PROGRAM -pauth.info '$LOGSTRING'"
        fi
      fi
      if [ -n "$LOG" ] ; then
        if [ "$DEBUG" = "y" ] ; then
          echo ssh $copy_files_TARGET "echo '`date +"%Y%m%d %H:%M:%S"` $LOGSTRING' >> $LOG"
        else
          ssh $copy_files_TARGET "echo '`date +"%Y%m%d %H:%M:%S"` $LOGSTRING' >> $LOG"
        fi
      fi
    else
      echo "$copy_files_TARGET: ERROR"
    fi
  fi
}

copy_cluster()
{
  copy_cluster_CLUSTER=$1
  copy_cluster_DEST=$2
  shift 2
  copy_cluster_SKIP=  #to skip the first word in the line
  copy_cluster_COUNT=0
  for copy_cluster_TARGET in `egrep "^$copy_cluster_CLUSTER" $CONF` ; do
    if [ -z "$copy_cluster_SKIP" ] ; then
      copy_cluster_SKIP=n
    else
      copy_files "$copy_cluster_TARGET" "$copy_cluster_DEST" $@
    fi
    copy_cluster_COUNT=$(($copy_cluster_COUNT + 1))
  done
  if [ 0 -eq $copy_cluster_COUNT ] ; then
    echo "Warning!  No cluster found with name $copy_cluster_CLUSTER" >&2
  fi
}

#source global config file
if [ -f $RC ] ; then
  . $RC
fi

while getopts C:dD:f:hH:t:vx OPTION
do
  case "$OPTION" in
  h) usage ; exit 1
  ;;
  v) echo $VERSION; exit 1
  ;;
  x) set -x; DEBUG=y; shift 1
  ;;
  C) GRP=$OPTARG; shift 2
  ;;
  d) DEBUG=y; shift 1
  ;;
  D) DEST=$OPTARG; shift 2
  ;;
  f) CONF=$OPTARG; shift 2
  ;;
  H) HOST=$OPTARG; shift 2
  ;;
  t) COMMENT=$OPTARG; shift 2
  ;;
  *) echo ; echo "!!!!!!Error.  Invalid option given" >&2; echo ; usage; exit 1
  ;;
  esac
done

if [ -z "$GRP" ] && [ -z "$HOST" ] ; then
  usage
  echo
  echo "Error.  You must specify a cluster or a host (-C or -H)!" >&2
  exit 1
fi

#do a sanity check on all files
if [ 0 -eq $# ] ; then
  usage
  echo "Error.  No files specified." >&2
  exit 1
fi
for f in $@ ; do
  if [ ! -r $f ] ; then
    echo "Error reading file $f.  Aborting transaction." >&2
    exit 1
  fi
  #build file list for log
  FILES="${FILES} `basename $f`"
done

if [ -n "$HOST" ] ; then
  CHECK=`echo $HOST | grep '@'`
  if [ -z "$CHECK" ] ; then  #target does not have format of user@host.  perhaps it is another cluster?
    echo "Error!  -H option must use format user@host: '$HOST' is invalid." >&2
    echo "If this is a cluster use the -C option." >&2
    exit 1
  fi
  #build log string
  LOGSTRING="$USER $PROGRAM:$COMMENT:$DEST $FILES"
  copy_files "$HOST" "$DEST" $@
fi

if [ -n "$GRP" ] ; then
  #build log string
  LOGSTRING="$USER $PROGRAM $GRP:$COMMENT:$DEST $FILES"
  if [ -r $ETC/$GRP.cfg ] ; then
    . $ETC/$GRP.cfg
  fi
  if [ -z "$SYSLOG" ] ; then
    SYSLOG=0
  fi

  if [ "$DEBUG" = "y" ] ; then
    echo "cluster IS '$GRP'"
  fi

  copy_cluster "$GRP" "$DEST" $@
fi
