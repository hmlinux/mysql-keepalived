#!/bin/bash
CHK_VIP=`ip addr| awk -F"[ :]+" '/192.168.6.176/{print $3}'`
if [ "$CHK_VIP" == "" ];then
cat > /etc/keepalived/scripts/check_mysql.sh << EOF
#!/bin/bash
if [ \`df -h |grep "/dev/sdb1"|wc -l\` -eq 0  ];then
    exit 0
elif ! killall -0 mysqld &>/dev/null;then
    exit 0
else
    exit 0
fi
EOF
else
cat > /etc/keepalived/scripts/check_mysql.sh << EOF
#!/bin/bash
if [ \`df -h |grep "/dev/sdb1"|wc -l\` -eq 0  ];then
    exit 1
elif ! killall -0 mysqld &>/dev/null;then
    pkill keepalived && exit 1
else
    exit 0
fi
EOF
fi
