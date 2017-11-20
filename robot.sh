#!/bin/bash

if [ $1 -gt 0 ] 2>/dev/null ;then
	echo start $1 client simulator
	i=0
	while [ $i -lt $1 ]
	do
	    i=`expr $i + 1`
		gnome-terminal.real  -e "./run -e env.cli -r S $i"
	done
else
	echo please enter a number larger then 0	
fi




