#!/bin/bash
interface="eth1"
VIP="172.16.10.28"
LOGFILE="/usr/local/keepalived/log/haswitch.log"
tmplog=/tmp/notify_.log
sharedisk="/dev/sdb1"
mount_point="/oradata"
HOSTNAME=$(hostname)
ORACLE_SID=HMODB

ORACLE_HOME=/u01/app/oracle/product/11.2.0/db_1

control_dir="/backup/oracle/control"
controlfile_path="$control_dir/control_$(date '+%Y%d%m%H%M%S')"
[ -d $control_dir ] || mkdir -p $control_dir && chown -R oracle:oinstall $control_dir


control_files="/oradata/HMODB/control01.ctl","/u01/app/oracle/flash_recovery_area/HMODB/control02.ctl","/home/oracle/rman/HMODB/control03.ctl"

[ -d $LOGDIR ] || mkdir $LOGDIR

info_log() {
    printf "$(date '+%b  %d %T %a') $HOSTNAME [keepalived_notify]: $1"
}

check_instance_is_open() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    sqlplus -S "/ as sysdba"
    SELECT STATUS FROM V\$INSTANCE;
    exit
EOF
}

startup_instance() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    sqlplus -S "/ as sysdba"
    startup
    exit
EOF
}

open_instance() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    sqlplus -S "/ as sysdba"
    alter database open;
    exit
EOF
}

mount_instance() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    sqlplus -S "/ as sysdba"
    alter database mount;
    exit
EOF
}

shutdown_instance() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    sqlplus -S "/ as sysdba"
    shutdown immediate
    exit
EOF
}

startup_nomount() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    sqlplus -S "/ as sysdba"
    startup nomount
    exit
EOF
}

startup_mount() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    sqlplus -S "/ as sysdba"
    startup mount
    exit
EOF
}

backup_controlfile() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    sqlplus -S "/ as sysdba"
    alter database backup controlfile to '$controlfile_path';
    exit
EOF
}

#runuser -l oracle -c "export ORACLE_SID=$ORACLE_SID;rman target / nocatalog cmdfile=/usr/local/keepalived/scripts/ControlfileRestore.sql"
restore_controlfile() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    rman target /
    RESTORE CONTROLFILE FROM '/oradata/HMODB/control01.ctl';
    exit
EOF
}

master() {
    info_log "Database Switch To MASTER\n"
    ismount=$(df -h | grep $sharedisk | grep $mount_point | wc -l)
    if [ $ismount -eq 0 ];then
        info_log "mount $sharedisk on $mount_point\n"
        mount $sharedisk $mount_point
        if [ $? -eq 0 ];then
            echo '' && sleep 1
            info_log "restore controlfile\n"
            startup_nomount
            restore_controlfile
        else
            info_log "Error: $sharedisk cannot mount or $mount_point busy\n"
            exit 1
        fi
    else
        disk=$(df -h | grep $mount_point | awk '{print $1}')
        if [ $disk == $sharedisk ];then
            info_log "mount: $sharedisk is already mounted on $mount_point\n"
        else
            info_log "Warning: $sharedisk already mounted on $disk\n"
        fi
    fi

    status=$(check_instance_is_open | grep -Eio -e "\bOPEN\b" -e "\bMOUNTED\b" -e "\bSTARTED\b")
    if [ "$status" == "OPEN" ];then
        info_log "a database already open by the instance.\n"
    elif [ "$status" == "MOUNTED" ];then
        info_log "re-open database instance\n"
        open_instance | tee $tmplog
        opened=$(cat $tmplog | grep -Eio "\bDatabase altered\b")
        if [ "$opened" != "Database altered" ];then
            info_log "Error: database instance open fail!\n"
            exit 2
        fi
    elif [ "$status" == "STARTED" ];then
        info_log "Alter database to mount\n"
        mount_instance | tee $tmplog
        mounted=$(cat $tmplog | grep -Eio "\bDatabase altered\b")
        if [ "$mounted" != "Database altered" ];then
            info_log "Database mount failed\n"
            exit 4
        else
            info_log "Alter database to open\n"
            open_instance | tee $tmplog
            opened=$(cat $tmplog | grep -Eio "\bDatabase altered\b")
            if [ "$opened" != "Database altered" ];then
                info_log "Database open failed\n"
                exit 4
            else
                info_log "Database opened.\n"
            fi
        fi
    else
        info_log "Startup database and open instance\n"
        startup_instance | tee $tmplog
        started=$(cat $tmplog | grep -Eio "\bDatabase opened\b")
        if [ "$started" != "Database opened" ];then
            info_log "Database instance open fail.\n"
            exit 4
        else
            info_log "Database opened.\n"
        fi
    fi

    info_log "start listener...\n"
    runuser -l oracle -c "lsnrctl status" &>/dev/null
    if [ $? -ne 0 ];then
        runuser -l oracle -c "lsnrctl start" &>/dev/null
        if [ $? -eq 0 ];then
            info_log "The listener startup successfully\n"
        else
            info_log "Listener start failure!\n"
       fi
    else
        info_log "listener already started.\n"
    fi
    echo
}

backup() {
    info_log "Database Switch To BACKUP\n"
    ismount=$(df -h | grep $sharedisk | grep $mount_point | wc -l)
    if [ $ismount -ge 1 ];then
        disk=$(df -h | grep $mount_point | awk '{print $1}')
        if [ $disk == $sharedisk ];then
            status=$(check_instance_is_open | grep -Eio -e "\bOPEN\b" -e "\bMOUNTED\b" -e "\bSTARTED\b")
            if [ "$status" == "OPEN" -o "$status" == "MOUNTED" ];then
                info_log "Database instance state is mounted\n"
                info_log "Backup current controlfile.\n"
                backup_controlfile
                info_log "Shutdown database instance, please wait...\n"
                shutdown_instance | tee $tmplog
                shuted=$(cat $tmplog | grep -Eio "\binstance shut down\b")
                if [ "$shuted" == "instance shut down" ];then
                    info_log "Database instance shutdown successfully.\n"
                else
                    info_log "Database instance shutdown failed.\n"
                fi
            elif [ "$status" == "STARTED" ];then
                info_log "Database instance state is STARTED\n"
                info_log "Shutdown database instance, please wait...\n"
                shutdown_instance | tee $tmplog
                shuted=$(cat $tmplog | grep -Eio "\binstance shut down\b")
                if [ "$shuted" == "instance shut down" ];then
                    info_log "Database instance shutdown successfully.\n"
                else
                    info_log "Database instance shutdown failed.\n"
                fi
            else
                info_log "Database instance not available."
            fi
    
            echo
            info_log "umount sharedisk\n"
            echo
            umount $mount_point
            if [ $? -eq 0 ];then
                info_log "umount $mount_point success.\n"
            else
                info_log "umount $mount_point fail!\n"
            fi
        else
            info_log "$sharedisk is not mount on $mount_point or busy."
        fi
    else
        info_log "$mount_point is no mount\n"
    fi

    info_log "stopping listener...\n"
    runuser -l oracle -c "lsnrctl status" &>/dev/null
    if [ $? -eq 0 ];then
        runuser -l oracle -c "lsnrctl stop" &>/dev/null
        if [ $? -eq 0 ];then
            info_log "The listener stop successfully\n"
        else
            info_log "Listener stop failure!\n"
       fi
    else
        info_log "listener is not started.\n"
    fi
    echo
}


notify_master() {
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify]: Transition to $1 STATE";
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify]: Setup the VIP on eth1 for $VIP";
}

notify_backup() {
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify]: Transition to $1 STATE";
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify]: removing the VIP on eth1 for $VIP";
}
case $1 in
        master)
                notify_master MASTER
                master
        ;;
        backup)
                notify_backup BACKUP
                backup
        ;;
        fault)
                notify_backup FAULT
		backup
        ;;
        stop)
                notify_backup STOP
                backup
        ;;
        *)
                echo "Usage: `basename $0` {master|backup|fault|stop}"
                exit 1
        ;;
esac
