#!/bin/bash
if [ `df -h |grep "/dev/sdb1"|wc -l` -eq 0  ];then
    exit 0
elif ! killall -0 mysqld &>/dev/null;then
    exit 0
else
    exit 0
fi
