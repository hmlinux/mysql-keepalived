#!/bin/bash
LOGDIR=/usr/local/keepalived/logs
LOGFILE="/usr/local/keepalived/logs/notify_scripts.log"
IPADDR=`ifconfig eth1 | awk -F"[: ]+" '/inet addr/{print $4}'`
VIP="192.168.6.176"
[ -d $LOGDIR ] || mkdir $LOGDIR

master() {
if [ `df -h |grep "/dev/sdb1"|wc -l` -eq 0 ];then
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify_script]: mount /dev/sdb1 /data ..."
    mount /dev/sdb1 /data && sleep 1
else
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify_script]: /data is mounted on /data"
fi

killall -0 mysqld &>/dev/null
if [ $? -ne 0 ];then
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify_script]: /etc/init.d/mysqld start..."
    /etc/init.d/mysqld start &>/dev/null
else
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify_script]: Mysqld is Running..."
fi

exit 0
}

backup() {
killall -0 mysqld &>/dev/null
if [ $? -eq 0 ];then
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify_script]: /etc/init.d/mysqld stop..."
    /etc/init.d/mysqld stop &>/dev/null
else 
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify_script]: Mysql Server is Not Running..."
fi

if [ `df -h |grep "/dev/sdb1"|wc -l` -ne 0 ];then
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify_script]: umount /data..."
    umount /data && sleep 1
else 
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify_script]: /data is not mount"
fi
}

notify_master() {
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify_script]: Transition to $1 STATE";
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify_script]: Setup the VIP on eth1 for $VIP";
}

notify_backup() {
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify_script]: Transition to $1 STATE";
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify_script]: removing the VIP on eth1 for $VIP";
}

case $1 in
        master)
                notify_master MASTER >>$LOGFILE
                master >>$LOGFILE
                exit 0
        ;;
        backup)
                notify_backup BACKUP >>$LOGFILE
                backup >>$LOGFILE
                exit 0
        ;;
        fault)
                notify_backup FAULT >>$LOGFILE
		backup >>$LOGFILE
                exit 0
        ;;
        stop)
                notify_backup STOP >>$LOGFILE
                backup >>$LOGFILE
                exit 0
        ;;
        *)
                echo "Usage: `basename $0` {master|backup|fault|stop}"
                exit 1
        ;;
esac
