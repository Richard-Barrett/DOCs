#!/bin/sh

##############################################################################################
# Config
##############################################################################################
BASEDIR="/misc/reickler/server_tests"
CONFDIR="${BASEDIR}/conf"
BINDIR="${BASEDIR}/bin"
SCRIPTNAME="$0"
DELIMITED_OUTPUT="/misc/reickler/server_tests/results/`hostname -s`.csv"

SUCCESS="echo -en \\033[1;32m"
FAILURE="echo -en \\033[1;31m"
WARNING="echo -en \\033[1;33m"
NORMAL="echo -en \\033[0;39m"

###############################################
# Functions
###############################################
usage() {
    echo "Usage: $0 -t <server type> [options]"
    echo "Options: "
    echo "  -c <config file> 	Specify which config file to use"
    echo "  -d 			Enable debugging"
    echo "  -h 			Show this help"
    echo "  -l <log file>		Specify which file to write logs to"
    echo "  -s <check>		Execute a single check of type <check>."
    echo " 			Valid checks for the -s option are:" 
    echo "				bios"
    echo "				cpus"
    echo "				dns"
    echo "				groups"
    echo "				kernel"
    echo "				kernel_modules"
    echo "				kernel_paramters"
    echo "				limits"
    echo "				memory"
    echo "				nfs_mounts"
    echo "				packages"
    echo "				services"
    echo "				swap"
    echo "				umask"
    echo "				users"

    echo
    exit
}

# Collect information about the machine to determine which values to use while testing
profile_machine() {

    RELEASE=`cat /etc/redhat-release | awk '{print $1, $2, $3, $4, $5, $6, $7}'`
    echo "Server is running $RELEASE"

    MODEL=`sudo /usr/sbin/dmidecode  | grep -i "product name: " | head -1 | awk -F ": " '{print $2}'`
    echo "Chassis model is $MODEL"
}

# Write a time-stamped log entry
logLine() {
    NOW=`date`
    ENTRY="$@"
    if [ "$LOGFILE" ]; then echo "[${NOW}] $ENTRY" >> $LOGFILE; fi
}

# Print out a green "OKAY" message
success() {
    echo -en \\033[60G
    echo -n "["; $SUCCESS; echo -n "OKAY"; $NORMAL; echo -n "]"; echo
}

# Print out a red "FAIL" message 
failure() {
    echo -en \\033[60G
    echo -n "["; $FAILURE; echo -n "FAIL"; $NORMAL; echo -n  "]"; echo
}

# Compare BIOS version with the version specified in the config file
check_bios() {

    echo -n " - Checking for BIOS version: "
    EXPECTED_BIOS_VERSION=${BIOS_VERSION}

    BIOS_VERSION=`sudo /usr/sbin/dmidecode | grep -A 2 "BIOS Information" | grep Version | awk '{print $NF}'`

    if [ "$BIOS_VERSION" == "$EXPECTED_BIOS_VERSION" ]; then
        logLine "[pass] [bios] Version $BIOS_VERSION matches"
        success
    else
        logLine "[fail] [bios] Expected $EXPECTED_BIOS_VERSION but got $BIOS_VERSION"
        failure
    fi 

    
}


# Check for the bladelogic agent
check_bladelogic()
{
    # Needs work...just a place holder so I don't forget the commands
    # /usr/nsh/sbin/version
    # /usr/nsh/sbin/agentctl list

    echo -n " - Checing Bladelogic Agent version: "

    BLADE_AGENT_VERSION=`/usr/nsh/sbin/version | head -1 | awk '{print $4}'`

    if [ "$BLADE_AGENT_VERSION" == "$EXPECTED_BLADE_AGENT_VERSION" ]; then
        logLine "[pass] [bladelogic] Version $BLADE_AGENT_VERSION matches"
        success
    else
        logLine "[fail] [bladelogic] Expected $EXPECTED_BLADE_AGENT_VERSION but got $BLADE_AGENT_VERSION"
        failure
    fi

}


# Check to see if the omreport binary exists
check_om() {
    echo -n " - Checking Dell Open Manage installation"
    if [ -e "$OMREPORT" ]; then
        logLine "[pass] [open manage] Found omreport binary"
        success
    else
        logLine "[fail] [open manage] Could not find omreport binary"
        failure
    fi
}

check_virtual_media() {
    echo -n " - Checking to see if virtual media is disabled"

    if [ -e "/usr/sbin/racadm" ]; 
    then
        VIRTUALMEDIA=`sudo /usr/sbin/racadm getconfig -g cfgRacVirtual | grep cfgVirMediaDisable | awk -F '=' '{print $2}'`
        if [ $VIRTUALMEDIA == 1 ]
        then
            logLine "[pass] [virtual media] Virtual Media has been disabled"
            success
        else
            logLine "[pass] [virtual media] Virtual Media is enabled"
            failure
        fi
    else
        logLine "[fail] [virtual media] /usr/sbin/racadm does not exist"
        failure
    fi
}

# Compare packages in the required package list with those installed on the system
check_packages() {

     # Check to see that all the expected packages are installed
     echo " - Checking for installed packages"

     PACKAGE_COUNT=0

     if [ -e "$RPMS" ]; then
         for i in `grep -v "^#" "$RPMS" | sed s/" "/"::DELIMITER::"/g`
         do
             EXPECTEDNAME=`echo $i | awk -F "::DELIMITER::" '{print $1}'`
             EXPECTEDVERSION=`echo $i | awk -F "::DELIMITER::" '{print $2}'`
             EXPECTEDARCH=`echo $i | awk -F "::DELIMITER::" '{print $3}'`
          
             let PACKAGE_COUNT+=1

             # Skip gpg keys and kernel - kernel is checked seperatly and gpg is different every time 
             if [ "$EXPECTEDNAME" == "kernel" ] || [ "$EXPECTEDNAME" == "gpg-pubkey" ]; then
                 continue
             fi
 
             FULLINFO=`rpm -q  --queryformat "%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n" $EXPECTEDNAME | grep ${EXPECTEDARCH}`
             RPMVERSION=`echo $FULLINFO | awk '{print $2}'`
 
             echo -n "  - ${EXPECTEDNAME} for ${EXPECTEDARCH} "
 
             if [ "$FULLINFO" == "" ]; then
                 echo -n "is not installed"
                 logLine "[fail] [rpm] ${EXPECTEDNAME} for ${EXPECTEDARCH} is not installed"
                 failure
             elif [ "$EXPECTEDVERSION" == "$RPMVERSION" ]
             then
                 echo -n "match"
                 logLine "[pass] [rpm] $EXPECTEDNAME $RPMVERSION == $EXPECTEDVERSION"
                 success
             else
                 # echo "${RPMVERSION} ${EXPECTEDVERSION}" | awk -f ${BINDIR}/version_compare.awk >/dev/null 2>&1
                 echo "${RPMVERSION} ${EXPECTEDVERSION}" | awk '{ exit ($1 > $2) ? 0 : 1  }' >/dev/null 2>&1
                 RETURN=$?

                 if [ $RETURN -eq 0 ]; then
                     echo -n "is newer than required"
                     logLine "[pass] [rpm] $EXPECTEDNAME $RPMVERSION > $EXPECTEDVERSION"
                     success
                 else
                     echo -n "is less than required"
                     logLine "[fail] [rpm] $EXPECTEDNAME $RPMVERSION < $EXPECTEDVERSION"
                     failure
                 fi
             fi
         done

         echo " - Checking total number of installed packages"

         INSTALLED_PACKAGE_COUNT=`rpm -qa | wc -l`
         echo -n "expected $PACKAGE_COUNT found $INSTALLED_PACKAGE_COUNT"

         # Figure out if hte number of expected packages matches the installed number
         if [ $PACKAGE_COUNT -lt $INSTALLED_PACKAGE_COUNT ]
         then 
             DIFF=( $INSTALLED_PACKAGE_COUNT - $PACKAGE_COUNT )
             logLine "[fail] [rpm] There are $DIFF extra packages installed"
             failure
         elseif [ $PACKAGE_COUNT -gt $INSTALLED_PACKAGE_COUNT ]
             DIFF=( $PACKAGE_COUNT - $INSTALLED_PACKAGE_COUNT )
             logLine "[fail] [rpm] There are $DIFF packages missing."
             failure
         else
             logLine "[pass] [rpm] Package count matches $PACKAGE_COUNT"
             success
         fi
      
     else 
         echo -n "Package list does not exist"
         logLine "[error] [config] Package list $RPMS does not exist"
         failure
     fi
}

# Check /etc/groups for the groups listed in teh config file
check_groups() {

    echo " - Checking for groups in /etc/groups file"

    for i in $( seq 1 ${#GROUPLIST[@]})
    do
        GROUP_NAME=`echo ${GROUPLIST[( ${i} - 1 )]} | awk -F ":" '{print $1}'`
        EXPECTED_GROUP_ID=`echo ${GROUPLIST[( ${i} - 1 )]} | awk -F ":" '{print $2}'`

        echo -n "  - ${GROUP_NAME} (${EXPECTED_GROUP_ID})"

        GROUP_ID=`sudo getent group ${GROUP_NAME} | awk -F ":" '{print $3}' 2>/dev/null`

        sudo getent group ${GROUP_NAME} > /dev/null 2>&1
        RETURN=$?

        if [ $RETURN -eq 0 ]
        then
            if [ "$EXPECTED_GROUP_ID" == "$GROUP_ID" ]
            then
                logLine "[pass] [group] Group ${GROUP_NAME} exists and matches GID ${GROUP_ID}"
                success
                echo "GROUP,${GROUP_NAME},$EXPECTED_GROUP_ID,exist,${GROUP_ID},exists" >> $DELIMITED_OUTPUT

            else 
                logLine "[fail] [group] Group ${GROUP_NAME} exists but GID ${EXPECTED_GROUP_ID} doesn't match ${GROUP_ID}"
                failure
                echo "GROUP,${GROUP_NAME},$EXPECTED_GROUP_ID,exist,${GROUP_ID},GID mismatch" >> $DELIMITED_OUTPUT
            fi
        else
            logLine "[fail] [group] Group ${GROUP_NAME} does not exist"
            failure
            echo "GROUP,${GROUP_NAME},$EXPECTED_GROUP_ID,exist,${GROUP_ID},group does not exist" >> $DELIMITED_OUTPUT
        fi
    done
}

# Check to see if the requested services are of the right state
check_services() {

    echo " - Checking service states"

    for i in $( seq 1 ${#SERVICELIST[@]})
    do
        SERVICE_NAME=`echo ${SERVICELIST[( ${i} - 1 )]} | awk -F ":" '{print $1}'`
        SERVICE_STATE=`echo ${SERVICELIST[( ${i} - 1 )]} | awk -F ":" '{print $2}'`

        echo -n "  - ${SERVICE_NAME} (${SERVICE_STATE})"

        if [ "$SERVICE_STATE" == "on" ] || [  "$SERVICE_STATE" == "enabled" ]
        then
            /sbin/chkconfig --list ${SERVICE_NAME} 2>/dev/null | grep "3:on" >/dev/null 2>&1
            SERVICE_CHKCONFIG=$?
        else
            /sbin/chkconfig --list ${SERVICE_NAME} 2>/dev/null | grep "3:off" >/dev/null 2>&1
            SERVICE_CHKCONFIG=$?
        fi

        if [ $SERVICE_CHKCONFIG -eq 0  ]
        then
            logLine "[pass] [service] ${SERVICE_NAME} is ${SERVICE_STATE}"
            success
        else
            logLine "[fail] [service] ${SERVICE_NAME} is not ${SERVICE_STATE}"
            failure
        fi
    done
}

# Check for the users listed in teh config file
check_users() {

    echo " - Testing user access"

    for i in $( seq 1 ${#USERLIST[@]})
    do
        USER_NAME=`echo ${USERLIST[( ${i} - 1 )]} | awk -F ":" '{print $1}'`
        USER_TYPE=`echo ${USERLIST[( ${i} - 1 )]} | awk -F ":" '{print $2}'`
        EXPECTED_USER_ID=`echo ${USERLIST[( ${i} - 1 )]} | awk -F ":" '{print $3}'`

        echo -n "  - ${USER_NAME} (${USER_TYPE})"

        # See if the user type is deny
        if [ "$USER_TYPE" == "deny" ]
        then
            echo foo | sudo /bin/su -c '/usr/bin/id -nu' ${USER_NAME} > /dev/null 2>&1
            RETURN=$?

            if [ $RETURN -ne 0 ]
            then
                logLine "[pass] [user] User ${USERLIST[( ${i} - 1 )]} does not have access"
                success
                echo "USER (${USER_TYPE}),${USER_NAME},$EXPECTED_USER_ID,deny,${USER_ID},denied" >> $DELIMITED_OUTPUT
            else
                logLine "[fail] [user] User ${USERLIST[( ${i} - 1 )]} has access but should be be denied"
                failure
                echo "USER (${USER_TYPE}),${USER_NAME},$EXPECTED_USER_ID,deny,${USER_ID},denied" >> $DELIMITED_OUTPUT
            fi
        else
            # Try to login as LDAP users but only check to see if the user exists for local accounts
            if [ "$USER_TYPE" == "ldap" ]
            then
                # Send some junk to stdin incase the users password expired
                USER_ID=`echo foo | sudo /bin/su -c '/usr/bin/id -u' ${USER_NAME} /dev/null 2>&1`

                echo foo | sudo /bin/su -c '/usr/bin/id -nu' ${USER_NAME} > /dev/null 2>&1
                RETURN=$?
            else
                EXPECTED_USER_ID=`sudo id -nu ${USER_NAME}`
                USER_ID=$EXPECTED_USER_ID

                sudo id -nu ${USER_NAME} > /dev/null 2>&1
                RETURN=$?
            fi

            if [ $RETURN -eq 0 ]
            then
                if [ "$EXPECTED_USER_ID" == "$USER_ID" ]
                then
                    logLine "[pass] [user] User ${USER_NAME} exists and has UID ${USER_ID}"
                    success
                    echo "USER (${USER_TYPE}),${USER_NAME},$EXPECTED_USER_ID,allow,${USER_ID},allowed" >> $DELIMITED_OUTPUT
                else
                    logLine "[fail] [user] User ${USER_NAME} exists but UID ${EXPECTED_USER_ID} an error occurred: ${USER_ID}"
                    failure
                    echo "USER (${USER_TYPE}),${USER_NAME},$EXPECTED_USER_ID,deny,${USER_ID},threw error" >> $DELIMITED_OUTPUT
                fi
            else
                logLine "[fail] [user] User ${USER_NAME} does not exist or cannot login"
                failure
                echo "USER (${USER_TYPE}),${USER_NAME},$EXPECTED_USER_ID,allow,${USER_ID},denied" >> $DELIMITED_OUTPUT
            fi
        fi
    done
}

check_kernel() {

    VALUE=`uname -r`

    echo -n " - Checking Kernel Release:"

    if [ "$VALUE" == "$KERNEL_VERSION" ]
    then
        logLine "[pass] [kernel version] The kernel version matches ${KERNEL_VERSION}"
        success
    else
        logLine "[fail] [kernel version] The kernel version ${VALUE} does not match the expected version ${KERNEL_VERSION}"
        failure
    fi

    echo "  - expected: $KERNEL_VERSION"
    echo "  - returned: $VALUE"
}

check_kernel_modules() {

    MODULES=(${KERNEL_MODULES[@]})

    # Check for loaded kernel modules
    echo " - Checking for loaded kernel modules"
    for i in $( seq 1 ${#MODULES[@]})
    do
        echo -n "  - ${MODULES[( ${i} - 1 )]}"
        sudo grep -c ${MODULES[( ${i} - 1 )]} /proc/modules >/dev/null
        RETURN=$?
        
        if [ $RETURN -eq 0 ]
        then
            logLine "[pass] [kernel module] Kernel Module ${MODULES[( ${i} - 1 )]} is loaded"
            success
        else
            logLine "[fail] [kernel module] Kernel Module ${MODULES[( ${i} - 1 )]} is not loaded"
            failure
        fi
    done
}

check_kernel_paramters() {

    echo " - Verify Kernel parameters:"

    RAMSIZE=`free -m | awk '{print $2}' | head -2 | tail -1`

    # shmmax should be 1/2 the total memory
    echo -n "  - SHMMAX"
    EXPECTED_SHMMAX=`echo "$RAMSIZE * 524288" | bc`
    SHMMAX=`cat /proc/sys/kernel/shmmax`
    if [ $SHMMAX -eq $EXPECTED_SHMMAX ]; then success; else echo -n " ${EXPECTED_SHMMAX} != ${SHMMAX}"; failure; fi

    echo -n "  - Hugepages"
    HUGEPAGE=`grep Hugepagesize /proc/meminfo | awk '{print $2}'`
    if [ "$HUGEPAGE" -eq 2048 ]; then success; else echo -n " ${HUGEPAGE} != 2048"; failure; fi

    # shmall should be ( shmmax / page size )
    echo -n "  - SHMALL"
    EXPECTED_SHMALL=`echo "${SHMMAX}/${HUGEPAGE}" | bc`
    SHMALL=`cat /proc/sys/kernel/shmall`
    if [ "$SHMALL" -eq "$EXPECTED_SHMALL" ]; then success; else echo -n " ${EXPECTED_SHMALL} != ${SHMALL}"; failure; fi

}

check_cpus() {

    echo "Checking CPU model and count"

    CPU_DATA=`cat /proc/cpuinfo | grep "model name" | awk -F ": " '{print $2}' | uniq -c`

    EXPECTED_CPU_COUNT=$CPU_COUNT
    EXPECTED_CPU_MODEL=$CPU_MODEL

    CPU_COUNT=`echo $CPU_DATA | awk '{print $1}'`
    CPU_MODE=`echo $CPU_DATA | awk -F "${CPU_COUNT} " '{print $2}'`

    echo -n " - CPU Count"  
    if [ $CPU_COUNT -eq $EXPECTED_CPU_COUNT ]
    then 
        logLine "[pass] [cpu count] The number of CPUs matches $EXPECTED_CPU_COUNT"
        success
    else
        logLine "[fail] [cpu count] The expected number of CPUs (${EXPECTED_CPU_COUNT}) does not match the installed count (${CPU_COUNT})"
        failure
    fi

    echo -n " - CPU Model"
    if [ "$CPU_MODEL" == "$EXPECTED_CPU_MODEL" ]
    then 
        logLine "[pass] [cpu model] The model of CPUs matches $EXPECTED_CPU_MODEL"
        success
    else
        logLine "[fail] [cpu model] The expected model of CPUs (${EXPECTED_CPU_MODEL}) does not match the installed model (${CPU_MODEL})"
        failure
    fi
}

check_memory() {

     EXPECTED_MEMTOTAL=$MEMTOTAL
     MEMTOTAL=`grep MemTotal /proc/meminfo | awk '{print $2}'`

    echo -n " - Checking total installed memory:"

    if [ $EXPECTED_MEMTOTAL -eq $MEMTOTAL ]
    then
        logLine "[pass] [memory] $MEMTOTAL KB installed"
        success
    else
        logLine "[fail] [memory] $MEMTOTAL installed but expected $EXPECTED_MEMTOTAL"
        failure
    fi

}

check_limits() {
    
    echo  " - Checking limits for Oracle user"

    sudo id -nu oracle > /dev/null 2>&1
    if [ $? -eq 0 ]
    then
 
        echo -n "  - memlock"
        MEMLOCK=`sudo su oracle -c "ulimit -l"`
        if [ "$MEMLOCK" == "unlimited" ]; then success; else failure; fi

        echo -n "  - virtual memory"
        VMEM=`sudo su oracle -c "ulimit -v"`
        if [ "$VMEM" == "unlimited" ]; then success; else failure; fi
    else
        logLine "[fail] [ulimit] Oracle user does not exist"
        failure
    fi
}

check_nfs_mounts() {

    echo " - Comparing mounted volumes with /etc/fstab"

    for volume in `grep nfs /etc/fstab | grep -v "^#" | sort | awk '{print $2}'`
    do
        echo -n "  - $volume"

        echo $volume | grep -v "^/oracr" >/dev/null 2>&1
        CRMVOL=$?

        echo $volume | grep -v "^/oradata" >/dev/null 2>&1
        DATAVOL=$?

	if [ $CRMVOL -eq 1 ]
        then
            EXPECTED_MOUNT_OPTIONS=(${CRM_MOUNT_OPTIONS[@]})
        elif [ $DATAVOL -eq 1 ]
        then
            EXPECTED_MOUNT_OPTIONS=(${DATA_MOUNT_OPTIONS[@]})
        else
            EXPECTED_MOUNT_OPTIONS=(${MOUNT_OPTIONS[@]})
        fi

        if [ "$DEBUG" == 1 ]; then echo "Expecting mount options: (${EXPECTED_MOUNT_OPTIONS[@]})"; fi

        if [ ! `grep $volume /etc/mtab >/dev/null 2>&1` ]
        then

            MOUNT_OPTIONS=()
            MATCHES=0

            # Ignore the orastaging volume cause it's not important
            if [ "$volume" == "/orastaging" ]; then success; continue; fi

            # Build an array from the mount options
            for option in `sudo grep $volume /etc/mtab | awk '{print $4}' | sed s/","/" "/g`
            do
                echo $option | grep "^addr=" >/dev/null 2>&1
                IS_ADDR=$?
               
                # Ignore the "addr=" option that's listed in mtab becuase it doesn't show up in fstab
                if [ $IS_ADDR -ne 0  ]
                then
                    MOUNT_OPTIONS=("${MOUNT_OPTIONS[@]}" $option)
                fi
            done

            # Loop through the mount options specified in the config and compare against what's mounted
            for i in $(seq 1 ${#EXPECTED_MOUNT_OPTIONS[@]} )
            do
                MATCH=0

                for j in $(seq 1 ${#MOUNT_OPTIONS[@]} )
                do
                    if [ "${MOUNT_OPTIONS[($j -1)]}" == "${EXPECTED_MOUNT_OPTIONS[($i -1)]}" ]
                    then
			MATCH=1
                        let MATCHES+=1
                    fi
                done

		if [ $MATCH -eq 1 ]
                then
                    logLine "[pass] [mount options] Found mount option ${EXPECTED_MOUNT_OPTIONS[($i -1)]} for volume $volume"
                else
                    logLine "[fail] [mount options] Missing mount option ${EXPECTED_MOUNT_OPTIONS[($i -1)]} for volume $volume"
                fi
            done

            if [ $MATCHES -eq ${#EXPECTED_MOUNT_OPTIONS[@]} ] && [ ${#EXPECTED_MOUNT_OPTIONS[@]} -eq ${#MOUNT_OPTIONS[@]} ]
            then 
                success
            else 
                logLine "[fail] [mount options] Expected ${#EXPECTED_MOUNT_OPTIONS[@]} mount options.  There are ${#MOUNT_OPTIONS[@]} with ${MATCHES} matches"
                failure
            fi

        else
            echo -n " is not mounted"
            failure
        fi
    done
}

check_umask() {

    echo -n " - Testing umask for oracle user"

    sudo id -nu oracle > /dev/null 2>&1
    if [ $? -eq 0 ]
    then
        if [ `sudo su oracle -c umask` -eq 022 ]; then success; else failure; fi
    else
        logLine "[fail] [umask] Oracle user does not exist"
        failure
    fi
}

check_swap() {
 
    echo -n " - Testing swap space"

    SWAPTOTAL=`free -m | grep "^Swap"| awk '{print $2}'`
    if [ $SWAPSIZE -eq $SWAPSIZE ]
    then
        logLine "[pass] [swap] Available swap is $SWAPSIZE as expected"
        success
    else
        logLine "[fail] [swap] Available swap is ${SWAPTOTAL}.  Was expecting ${SWAPSIZE}."
        failure
    fi
}

check_dns() {

    echo " - Testing name resolution"

    for INTERFACE in `sudo grep -il "ONBOOT=yes" /etc/sysconfig/network-scripts/ifcfg-* | awk -F "-" '{print $NF}' | grep -wv lo`
    do
        ADDRESS=`/sbin/ifconfig  $INTERFACE | grep "inet addr" | awk -F ":" '{print $2}' | awk '{print $1}'`
        PTR=`echo $ADDRESS | awk -F "." '{print $4 "."  $3 "." $2 "."  $1 ".in-addr.arpa"}'`

        echo " - ${INTERFACE} - ${ADDRESS}"

        if [ "$ADDRESS" == "" ]
        then 
            echo -n "  - There doesn't appear to be an IP on ${INTERFACE}"
            failure

            logLine "[fail] [nic] There doesn't appear to be an IP address assigned on ${INTERFACE}"
            continue
        fi

        if [ "$INTERFACE" != "bond1" ] && [ "$ADDRESS" != "$NFSADDRESS" ]
        then
	    NFSADDRESS=$ADDRESS
            echo -n "  - /etc/hosts entry"
            grep -v "^#" /etc/hosts | grep "${ADDRESS}" >/dev/null 2>&1
            RETURN=$?

            if [ $RETURN -eq 0 ]
            then
                HOST_ENTRY=`grep "${ADDRESS}" /etc/hosts`
                EXPECTED_HOSTNAME=`host "${ADDRESS}" | tail -1 | awk '{print $NF}' | sed s/"\.$"//g`
                EXPECTED_SHORT_HOSTNAME=`echo $HOSTNAME | cut -d '.' -f1`

                HOSTNAME=`echo $HOST_ENTRY | awk '{print $2}'`
                SHORT_HOSTNAME=`echo $HOST_ENTRY | awk '{print $3}'`

                if [ $DEBUG ]; then echo; fi

                if [ $DEBUG ]; then echo "Expected Hostname; $EXPECTED_HOSTNAME"; fi
                if [ $DEBUG ]; then echo "Expected Short ame; $EXPECTED_SHORT_HOSTNAME"; fi

                if [ $DEBUG ]; then echo "Hostname; $HOSTNAME"; fi
                if [ $DEBUG ]; then echo "Hostname; $SHORT_HOSTNAME"; fi
  
                if [ "$EXPECTED_HOSTNAME" == "$HOSTNAME" ] && [ "$EXPECTED_SHORT_HOSTNAME" == "$SHORT_HOSTNAME" ]
                then
                    logLine "[pass] [hosts file] Found correct entry for ${ADDRESS} in /etc/hosts."
                    success
                else
                    logLine "[fail] [hosts file] Found an entry for ${ADDRESS} in /etc/hosts, but it is in the wrong format."
                    failure
                fi
            else
                logLine "[fail] [hosts file] Entry for ${ADDRESS} was not found in /etc/hosts."
                failure
            fi
        fi

        echo ${ADDRESS} | grep '^192\.168\.' >/dev/null 2>&1
        PRIVATE=$?

        if [ $PRIVATE -ne 0 ]
        then

            for i in $( seq 1 ${#NAMESERVERS[@]})
            do

                echo -n "  - Checking for ${NAMESERVERS[( ${i} - 1 )]} in /etc/resolv.conf"
                
                grep ${NAMESERVERS[( ${i} - 1 )]} /etc/resolv.conf >/dev/null 2>&1
                RETURN=$?

                if [ $RETURN -eq 0 ]
                then
                    logLine "[pass] [dns] Found ${NAMESERVERS[( ${i} - 1 )]} in /etc/resolv.conf"
                    success
                else
                    logLine "[fail] [dns] ${NAMESERVERS[( ${i} - 1 )]} was not found in /etc/resolv.conf"
                    failure
                fi
                
                echo -n "  - reverse lookup using ${NAMESERVERS[( ${i} - 1 )]}"
                HOSTNAME=`host $ADDRESS ${NAMESERVERS[( ${i} - 1 )]} | tail -1 | awk '{print $NF}' | sed s/"\.$"//g`
                if [ "$HOSTNAME" == "3(NXDOMAIN)" ] || [ "$HOSTNAME" == "reached" ]
                then 
                    logLine "[fail] [dns] Lookup 'host ${ADDRESS} ${NAMESERVERS[( ${i} - 1 )]}' returned ${HOSTNAME}"
                    failure
                else
                    logLine "[pass] [dns] Lookup 'host ${ADDRESS} ${NAMESERVERS[( ${i} - 1 )]}' returned ${HOSTNAME}"
                    success
            
                    echo -n "  - forward lookup using ${NAMESERVERS[( ${i} - 1 )]}"
                    REVERSE=`host $HOSTNAME ${NAMESERVERS[( ${i} - 1 )]} | tail -1 | awk '{print $NF}'`
                    if [ "${REVERSE}" == "${ADDRESS}" ]
                        logLine "[pass] [dns] Lookup 'host ${HOSTNAME} ${NAMESERVERS[( ${i} - 1 )]}' returned ${REVERSE}"
                        then success
                    else
                        logLine "[fail] [dns] Lookup 'host ${HOSTNAME} ${NAMESERVERS[( ${i} - 1 )]}' returned ${REVERSE}"
                        ailure
                    fi
                fi

            done
        fi

    done
}

readconfig() {

    if [ ! "$CONFIGFILE" ] ; then CONFIGFILE="${CONFDIR}/main.conf"; fi
 
    # Read the config file for the server type specified
    if [ -e "${CONFIGFILE}" ]; then
        echo "Reading configuration from ${CONFIGFILE}"
        . ${CONFIGFILE}
    else
        echo "${CONFIGFILE} does not exist"
        exit
    fi

}


main() {

    echo "Log file being written as $LOGFILE"
    logLine "============================ $SCRIPTNAME Started ==================================="

    # if [ "$DEBUG" == 1 ]; then set -x; set -v; fi

    # Read the appropriate configuration file 
    readconfig;

    # Execute a few commands to populate variables about the machine like model, etc.
    profile_machine;

    if [ "$CHECK_USERS" == 1 ]; then check_users; fi
    if [ "$CHECK_GROUPS" == 1 ]; then check_groups; fi
    if [ "$CHECK_PACKAGES" == 1 ]; then check_packages; fi
    if [ "$CHECK_SERVICES" == 1 ]; then check_services; fi
    if [ "$CHECK_DNS" == 1 ]; then check_dns; fi
    if [ "$CHECK_NFS_MOUNTS" == 1 ]; then check_nfs_mounts; fi
    if [ "$CHECK_KERNEL_RELEASE" == 1 ]; then check_kernel; fi
    if [ "$CHECK_KERNEL_MODULES" == 1 ]; then check_kernel_modules; fi
    if [ "$CHECK_KERNEL_PARAMETERS" == 1 ]; then check_kernel_paramters; fi
    if [ "$CHECK_UMASK" == 1 ]; then check_umask; fi
    if [ "$CHECK_LIMITS" == 1 ]; then check_limits; fi
    if [ "$CHECK_OPENMANAGE" == 1 ]; then check_om; fi
    if [ "$CHECK_VIRTUALMEDIA" == 1 ]; then check_virtual_media; fi
    if [ "$CHECK_BIOS" == 1 ]; then check_bios; fi
    if [ "$CHECK_MEMORY" == 1 ]; then check_memory; fi
    if [ "$CHECK_SWAP" == 1 ]; then check_swap; fi
    if [ "$CHECK_CPU" == 1 ]; then check_cpus; fi
    if [ "$CHECK_BLADELOGIC" == 1 ]; then check_bladelogic; fi

    echo
    echo

    logLine "============================ $SCRIPTNAME Finished ==================================="

    if [ "$LOGFILE" ]; then cat $LOGFILE; fi
}


# Check command line arguments
while getopts "c:dhl:s:" Option
do
    case $Option in
	d ) DEBUG=1 ;;
        c ) CONFIGFILE=$OPTARG ;;
        h ) usage ;;
        l ) LOGFILE=$OPTARG ;;
        s ) SINGLECHECK=$OPTARG ;;
    esac
done

# Decrements the argument pointer so it points to next argument
shift $(($OPTIND - 1))

if [ "$SINGLECHECK" ]
then
    readconfig
    profile_machine
    check_${SINGLECHECK}
else
    main
fi


