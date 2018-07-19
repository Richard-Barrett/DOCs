#!/bin/bash 

#copied from http://www.scottklarr.com/topic/70/linux-m4a-to-mp3-converter-shell-script/

for i in *.m4a
do 
echo "Converting: ${i%.m4a}.mp3" 
faad -o - "$i" | lame - "${i%.m4a}.mp3" 
done
