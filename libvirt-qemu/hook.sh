#!/bin/bash

# Save this file as /etc/libvirt/hooks/qemu (you may need to create /etc/libvirt/hooks)

# tuneables
SCREENSES=vcons         # screen session name we plug in to
DOM0CMD="/bin/bash -i"  # what to run for the dom0 screen session
ACTION=${2}
DOMNAME=${1}

case ${ACTION} in

        "started")
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
                        # delay for libvirt to settle, backgrounded to not race the domain creation...
                        echo -n "screen -S ${SCREENSES} -X eval 'screen -t " >> $TMPFILE
                else
                        # plug into the first screen session we found
                        echo -n "screen -S ${SCREENPID} -X eval 'screen -t " >> $TMPFILE
                fi
                echo "${DOMNAME} virsh console ${DOMNAME}'" >> $TMPFILE
                echo "rm ${TMPFILE}" >> ${TMPFILE}
                chmod +x $TMPFILE
                nohup $TMPFILE > /dev/null &
                ;;
        *)
                ;;
esac

# we really want virsh to start the domain regardless
exit 0
