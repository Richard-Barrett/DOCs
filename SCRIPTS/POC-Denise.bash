#! /bin/bash
#*****************************************************************
# Name: IliketocallhimBob
#
# Purpose: this is a POC for doing war file changes automagically
#
# Usage: ./IliketocallhimBob
#
# Author	      Date	    Version    Comments
# ---------------+----------------+---------+--------------------
#   --siggy           7Aug15        .001      initial pass
#
#****************************************************************

#WHEN=`echo $(date +%d%b%y"-"%H:%M:%S)`

#First we ask the FQPN of the origination file
echo "Please enter the FQPN for the origination file."
read FROMfile

if [ -e $FROMfile ]; then
  echo "$FROMfile exists...moving on."  
else 
    echo "nonexistent file of $FROMfile.... exiting"
    exit 0
fi

echo 
echo "Please enter the FQPN for the destination file."
read TOfile

if [ -e $TOfile ]; then
  echo "$TOfile exists...moving on."  
else 
    echo "nonexistent file of $FROMfile.... exiting"
    exit 0
fi

path=$(dirname "${FROMfile}")
file=basename "${FROMfile}"

#backup existing FROMfile if it fails bail and send email
mv $FROMfile $FROMfile.ORIG
if [ $? -ne 0 ]; then
    echo "Move failed exiting"
    mail -s "Backup FAILED update not completed" deniseba@ri-net.com -c limd@ri-net.com
    exit 0
else
    rm -rf $FROMfile
    cp -r $TOfile $path
fi

#If copy fails revert back to original FROMfile  
if [ $? -ne 0 ]; then
    mv $FROMfile.ORIG $FROMfile
fi

#Send mail upon completion
    mail -s "Update completed successfully" deniseba@ri-net.com -c limd@ri-net.com