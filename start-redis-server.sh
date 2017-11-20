#!/bin/bash

list="8801 8802 8803 8804 8805"
for i in $list; do
    echo start redis on port: $i
    redis-server dbconf/$i.conf
done
