#!/bin/sh

spid=`ps -e | grep skynet | awk '{print $1}'`

if test -n "$spid" ; then
	echo kill skynet pid: $spid
	kill $spid
else
	echo "process not found"
fi
