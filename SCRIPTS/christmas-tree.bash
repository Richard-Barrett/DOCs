#!/bin/bash


#christmas-tree.bash
#25Jan16
#Somehow I got a bug up my ass about ascii art via script.  Start with bash and re-teach myself perl.
#This is a double loop to print out a Christmas tree

echo "How big do you want the tree to be?"
read IN

#count up
#for ((c=1;c<=5;c++)); do echo $c; done

#count down
#for ((c=5;c>=1;c--)); do echo $c; done

for ((c=1;c<=IN;c++)); do echo $c; done
