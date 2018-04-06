#!/bin/bash
if [ `df -h |grep "/dev/sdb1"|wc -l` -eq 0  ];then
    exit 1
elif ! killall -0 mysqld &>/dev/null;then
    pkill keepalived && exit 1
else
    exit 0
fi
