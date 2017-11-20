#!/bin/bash

for file in `svn status  | awk '{print $2}' | grep '\.lua' | grep -v '\.swp'`;
do
    echo ${file}
    luacheck -q ${file}
done

