#!/bin/bash

# tuneables
SCREENSES=xen           # screen session name we plug in to
DOM0CMD="/bin/bash -i"  # what to run for the dom0 screen session
DELAY="3"               # delay (in seconds) before attempting to plug a xm console into screen
XM="/usr/sbin/xm"       # path to 'xm' command

case ${ACTION} in

        "add")
                T=${DEVPATH:17} # strip /devices/console-
                DOMID=${T%-0} # strip -0
                DOMNAME=`xm domname ${DOMID}`
                # wipe any existing dead screen sessions
                screen -wipe ${SCREENSES}
                # do I have a screen session already?
                SCREENPID=`screen -ls ${SCREENSES} | grep ${SCREENSES} | head -n 1 | awk '{ print $1 }'`
                TMPFILE=`/bin/mktemp`
                echo "#!/bin/bash" > $TMPFILE
                echo "sleep ${DELAY}" >> $TMPFILE
                if [ "x${SCREENPID}" == "x" ]; then
                        # try to start screen
                        screen -U -d -m -S ${SCREENSES} -t `uname -n` ${DOM0CMD}
                        # plug a new window for the domU into screen
                        # delay for xen to settle, backgrounded to not race the domain creation...
                        echo -n "screen -S ${SCREENSES} -X eval 'screen -t " >> $TMPFILE
                else
                        # plug into the first screen session we found
                        echo -n "screen -S ${SCREENPID} -X eval 'screen -t " >> $TMPFILE
                fi
                echo "${DOMNAME} ${XM} console ${DOMID}'" >> $TMPFILE
                echo "rm ${TMPFILE}" >> ${TMPFILE}
                chmod +x $TMPFILE
                nohup $TMPFILE > /dev/null &
                ;;
        *)
                ;;
esac

# we really want xen to start the domain regardless
exit 0
