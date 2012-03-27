#!/bin/bash

# assumes you replaced bin/java!
env >> /tmp/jncwrapper.out

_JRE_PATH="${HOME}/hbin/`uname -n`/java7"

if [ $3x = "NCx" ] ; then
	$_JRE_PATH/32bit/bin/java "$@"
else
	$_JRE_PATH/64bit/bin/java.bin "$@"
fi
