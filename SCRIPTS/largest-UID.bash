#!/bin/bash

LARGESTUID=`cat /etc/passwd | awk -F: '{print $3}' | grep -v 65534 |sort -n| tail -1`
NEXTUID=$(($LARGESTUID + 1))
#(02:22:33 PM) meadrocks: let NEXTUID=$LARGESTUID+1
#(02:23:02 PM) meadrocks: the let command tells bash to do integer math, not string conatination


echo $NEXTUID