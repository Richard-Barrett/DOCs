#!/bin/bash

##############################################################################################
# majority of code stolen from Ron's system test script
#
# 6may09  --siggy
#
##############################################################################################

OUTPUT="/misc/dsiegfriedt/MACHINES/$HOSTNAME"

# Print date at top of info file
    echo "##############################################################################################" >> $OUTPUT
	date +%A" "%B" "%e", "%C%y" "%I":"%M" "%p >> $OUTPUT
    echo "##############################################################################################" >> $OUTPUT

# short name requested by Kim Ho 8may09
    echo "Short name is "`hostname -s` >> $OUTPUT
    echo "##############################################################################################" >> $OUTPUT

# FQHN requested by Kim Ho 8may09
    echo "FQHN is "`hostname` >> $OUTPUT
    echo "##############################################################################################" >> $OUTPUT

# Local disk size requested by Kim Ho 8may09
    dmesg | grep SCSI | grep sd >> $OUTPUT
    echo "##############################################################################################" >> $OUTPUT

# Collect version of RedHat installed
    RELEASE=`cat /etc/redhat-release`
    echo "Server is running $RELEASE" >> $OUTPUT
    echo "##############################################################################################" >> $OUTPUT

# Collecting kernel version
    VALUE=`uname -a | awk '{print $1" "$2" "$3}'`
    echo "uname -a = $VALUE" >> $OUTPUT
    echo "##############################################################################################" >> $OUTPUT

# Collect machine model number
    MODEL=`sudo /usr/sbin/dmidecode  | grep -i "product name: " | head -1 | awk -F ": " '{print $2}'`
    echo "Chassis model is $MODEL" >> $OUTPUT
    echo "##############################################################################################" >> $OUTPUT

# Compare BIOS version with the version specified in the config file
    BIOS_VERSION=`sudo /usr/sbin/dmidecode | grep -A 2 "BIOS Information" | grep Version | awk '{print $NF}'`
    echo "BIOS version is $BIOS_VERSION" >> $OUTPUT
    echo "##############################################################################################" >> $OUTPUT

# Check for the bladelogic agent
    BLADE_AGENT_VERSION=`/usr/nsh/sbin/version | head -1 | awk '{print $4}'`
    echo "Bladelogic Agent version is $BLADE_AGENT_VERSION" >> $OUTPUT
    echo "##############################################################################################" >> $OUTPUT

# Memory size in MB.
    RAMSIZE=`free -m | awk '{print $2}' | head -2 | tail -1`
    echo "RAMSIZE is $RAMSIZE MB" >> $OUTPUT
    echo "##############################################################################################" >> $OUTPUT

# check_memory
    MEMTOTAL=`cat /proc/meminfo | grep -i memtotal | awk '{print $2}'`
    echo "Total installed memory is $MEMTOTAL B" >> $OUTPUT
    echo "##############################################################################################" >> $OUTPUT

# check_swap
    SWAPTOTAL=`free -m | grep "^Swap"| awk '{print $2}'`
    echo "Swap space is $SWAPTOTAL MB" >> $OUTPUT
    echo "##############################################################################################" >> $OUTPUT
    
# check_cpus
    CPU_DATA=`cat /proc/cpuinfo | grep "model name" | awk -F ": " '{print $2}' | uniq -c`
    echo "CPU info is $CPU_DATA" >> $OUTPUT
    echo "##############################################################################################" >> $OUTPUT

# Collect all IP addresses from the machine
    /sbin/ifconfig | grep -A1 eth >> $OUTPUT
    /sbin/ifconfig | grep -A1 bond >> $OUTPUT

# Requires that "racadm" is installed.  Commenting out for now
#check_virtual_media() {
#    echo " - Checking to see if virtual media is disabled"

#    if [ -e "/usr/sbin/racadm" ]; 
#    then
#        VIRTUALMEDIA=`sudo /usr/sbin/racadm getconfig -g cfgRacVirtual | grep cfgVirMediaDisable | awk -F '=' '{print $2}'`
#        if [ $VIRTUALMEDIA == 1 ]
#        then
#            logLine "[pass] [virtual media] Virtual Media has been disabled"
#            success
#        else
#            logLine "[pass] [virtual media] Virtual Media is enabled"
#            failure
#        fi
#    else
#        logLine "[fail] [virtual media] /usr/sbin/racadm does not exist"
#        failure
#    fi
#}

# This looks interesting but I just want basic information.  I will comment it out for now.
# check_dns() {
#
#    echo " - Testing name resolution"
#
#    for INTERFACE in `sudo grep -il "ONBOOT=yes" /etc/sysconfig/network-scripts/ifcfg-* | awk -F "-" '{print $NF}' | grep -wv lo`
#    do
#        ADDRESS=`/sbin/ifconfig  $INTERFACE | grep "inet addr" | awk -F ":" '{print $2}' | awk '{print $1}'`
#        PTR=`echo $ADDRESS | awk -F "." '{print $4 "."  $3 "." $2 "."  $1 ".in-addr.arpa"}'`
#
#        echo " - ${INTERFACE} - ${ADDRESS}"
#
#        if [ "$ADDRESS" == "" ]
#        then 
#            echo "  - There doesn't appear to be an IP on ${INTERFACE}"
#            failure
#
#            logLine "[fail] [nic] There doesn't appear to be an IP address assigned on ${INTERFACE}"
#            continue
#        fi
#
#        if [ "$INTERFACE" != "bond1" ] && [ "$ADDRESS" != "$NFSADDRESS" ]
#        then
#	    NFSADDRESS=$ADDRESS
#            echo "  - /etc/hosts entry"
#            grep -v "^#" /etc/hosts | grep "${ADDRESS}" >/dev/null 2>&1
#            RETURN=$?
#
#            if [ $RETURN -eq 0 ]
#            then
#                HOST_ENTRY=`grep "${ADDRESS}" /etc/hosts`
#                EXPECTED_HOSTNAME=`host "${ADDRESS}" | tail -1 | awk '{print $NF}' | sed s/"\.$"//g`
#                EXPECTED_SHORT_HOSTNAME=`echo $HOSTNAME | cut -d '.' -f1`
#
#                HOSTNAME=`echo $HOST_ENTRY | awk '{print $2}'`
#                SHORT_HOSTNAME=`echo $HOST_ENTRY | awk '{print $3}'`
#
#                if [ $DEBUG ]; then echo; fi
#
#                if [ $DEBUG ]; then echo "Expected Hostname; $EXPECTED_HOSTNAME"; fi
#                if [ $DEBUG ]; then echo "Expected Short ame; $EXPECTED_SHORT_HOSTNAME"; fi
#
#                if [ $DEBUG ]; then echo "Hostname; $HOSTNAME"; fi
#                if [ $DEBUG ]; then echo "Hostname; $SHORT_HOSTNAME"; fi
#  
#                if [ "$EXPECTED_HOSTNAME" == "$HOSTNAME" ] && [ "$EXPECTED_SHORT_HOSTNAME" == "$SHORT_HOSTNAME" ]
#                then
#                    logLine "[pass] [hosts file] Found correct entry for ${ADDRESS} in /etc/hosts."
#                    success
#                else
#                    logLine "[fail] [hosts file] Found an entry for ${ADDRESS} in /etc/hosts, but it is in the wrong format."
#                    failure
#                fi
#            else
#                logLine "[fail] [hosts file] Entry for ${ADDRESS} was not found in /etc/hosts."
#                failure
#            fi
#        fi
#
#        echo ${ADDRESS} | grep '^192\.168\.' >/dev/null 2>&1
#        PRIVATE=$?
#
#        if [ $PRIVATE e 0 ]
#        then
#
#            for i in $( seq 1 ${#NAMESERVERS[@]})
#            do
#
#                echo "  - Checking for ${NAMESERVERS[( ${i} - 1 )]} in /etc/resolv.conf"
#                
#                grep ${NAMESERVERS[( ${i} - 1 )]} /etc/resolv.conf >/dev/null 2>&1
#                RETURN=$?
#
#                if [ $RETURN -eq 0 ]
#                then
#                    logLine "[pass] [dns] Found ${NAMESERVERS[( ${i} - 1 )]} in /etc/resolv.conf"
#                    success
#                else
#                    logLine "[fail] [dns] ${NAMESERVERS[( ${i} - 1 )]} was not found in /etc/resolv.conf"
#                    failure
#                fi
#                
#                echo "  - reverse lookup using ${NAMESERVERS[( ${i} - 1 )]}"
#                HOSTNAME=`host $ADDRESS ${NAMESERVERS[( ${i} - 1 )]} | tail -1 | awk '{print $NF}' | sed s/"\.$"//g`
#                if [ "$HOSTNAME" == "3(NXDOMAIN)" ] || [ "$HOSTNAME" == "reached" ]
#                then 
#                    logLine "[fail] [dns] Lookup 'host ${ADDRESS} ${NAMESERVERS[( ${i} - 1 )]}' returned ${HOSTNAME}"
#                    failure
#                else
#                    logLine "[pass] [dns] Lookup 'host ${ADDRESS} ${NAMESERVERS[( ${i} - 1 )]}' returned ${HOSTNAME}"
#                    success
#            
#                    echo "  - forward lookup using ${NAMESERVERS[( ${i} - 1 )]}"
#                    REVERSE=`host $HOSTNAME ${NAMESERVERS[( ${i} - 1 )]} | tail -1 | awk '{print $NF}'`
#                    if [ "${REVERSE}" == "${ADDRESS}" ]
#                        logLine "[pass] [dns] Lookup 'host ${HOSTNAME} ${NAMESERVERS[( ${i} - 1 )]}' returned ${REVERSE}"
#                        then success
#                    else
#                        logLine "[fail] [dns] Lookup 'host ${HOSTNAME} ${NAMESERVERS[( ${i} - 1 )]}' returned ${REVERSE}"
#                        ailure
#                    fi
#                fi
#
#            done
#        fi
#
#    done
#}

