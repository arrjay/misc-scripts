#!/bin/bash

if [ $(whoami -u) != "root" ]; then
  echo "this script needs to be run as root to modify accounts"
fi

# first, add the groups
for x in $(echo *.group) ; do
  groupent=${x}
  group=$(awk -F ':' '{ print $1 }' ${groupent})
  # see if said group exists first
  getent group ${group} > /dev/null
  if [ $? -ne 0 ]; then
    gid=$(awk -F ':' '{ print $3 }' ${groupent})
    groupadd -g ${gid} ${group}
  fi
done

# next, add the users
for x in $(echo *.passwd) ; do
  pwent=${x}
  user=$(awk -F ':' '{ print $1 }' ${pwent})
  pass='!!'
  # see if said user exists first
  getent passwd ${user} > /dev/null
  if [ $? -ne 0 ]; then
    uid=$(awk -F ':' '{ print $3 }' ${pwent})
    shell=$(awk -F ':' '{ print $7 }' ${pwent})
    # set the password hash if we have one
    if [ -f ${user}.shadow ]; then
      pass=$(awk -F ':' '{ print $2 }' ${user}.shadow)
    fi
    useradd -u ${uid} -g ${user} -p ${pass} -s ${shell} ${user}
  fi
  # add SSH keys if they exist
  if [ -f ${user}.pub ]; then
    userhome=$(getent passwd ${user}|awk -F ':' '{ print $6 }')
    sudo -u ${user} mkdir ${userhome}/.ssh
    echo ${user}.pub | sudo -u ${user} tee -a ${userhome}/.ssh/authorized_keys > /dev/null
  fi
done

# add users to groups...
for x in $(echo *.group) ; do
  groupent=${x}
  memberslist=$(awk -F ':' '{ print $4 }' ${groupent})
  group=$(awk -F ':' '{ print $1 }' ${groupent})
  for x in $(echo ${memberslist}|sed -e 's/,/ /g') ; do
    usermod -a -G ${group} ${x}
  done
done
