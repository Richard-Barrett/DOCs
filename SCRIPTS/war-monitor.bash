#!/bin/bash
#26Feb14  --siggy

#requested by DonA 21Feb14 to be run as a cron daily
WHEN=`echo $(date +%d%b%C%y"-"%H:%M)`

printf '%s %21s %s\n' Hostname Run Time 
printf '%s %20s %s\n' `hostname` $WHEN
ls -l  /usr/tomcat/apache-tomcat-6.0.29/webapps/cc.war
#ls -l /etc/sysconfig/network-scripts/ifcfg-em1
echo
