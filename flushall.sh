#!/bin/bash

list="8801 8802 8803 8804 8805"
for i in $list; do
    echo flush redis on port: $i
    redis-cli -p $i FLUSHALL
done
