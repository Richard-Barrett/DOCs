#!/bin/bash

#RH assessment asked for a script the took a -c flag followed by what the tranistion should be all uppercase or all lowercase.

#$@ 	This contains the values of all of hte arguments passed to a script. 

if ( $# -eq 0 ); then
    echo "The following flags need to be added to the command.\n The -c to engage the command and  upper or lower depending on desire effect.\n\n\n" 
else

if ( $# -ne 2); then
    echo "not the correct number of arguments"
else
case "$2" in
"lower")
    ls <full-path-name> | tr "A-Z" "a-z"
    ;;
"upper")
    ls <full-path-name> | tr "a-z" "A-Z"
    ;;
*)
    echo "don't know what this is"
    ;;
esac
fi #check correct number of args

fi #check for 0 flags