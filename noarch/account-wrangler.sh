#!/bin/sh

if [ $(uname -s) == "VMkernel" ]; then
  if [ "${USER}" != "root" ]; then
    echo "this script needs to be run as root to modify accounts"
    exit 2
  fi
else
  if [ $(whoami) != "root" ]; then
    echo "this script needs to be run as root to modify accounts"
    exit 2
  fi
fi

# declare overrides if needed
if [ $(uname -s) == "VMkernel" ]; then
  vmkmaj=$(uname -r|sed s'/\..*//')
  if [ $vmkmaj -lt "6" ]; then
    groupadd() {
      _group=
      _gid=
      while getopts "g:" _opt; do
        case ${_opt} in
          g)
            _gid=${OPTARG}
            ;;
        esac
      done
      if [ $OPTIND -gt 1 ]; then
        shift $(($OPTIND - 1))
        _group=${1}
      fi
      # cheat. cheat badly.
      echo "${_group}:x:${_gid}:" >> /etc/group
    }
    getent() {
      database=${1}
      case ${database} in
        group|passwd|shadow)
          entity=${2}
          grep ^"${entity}": /etc/${database}
          ;;
        *)
          echo "I didn't expect ${database}!"
          ;;
      esac
    }
    # overloaded because the builtin doesn't do passwords
    useradd() {
      _user=
      _uid=
      _pass=
      _group=
      _comment=
      _shell=/bin/ash
      OPTIND=1
      while getopts "u:g:p:s:c:" _opt; do
        case ${_opt} in
          u)
            _uid=${OPTARG}
            ;;
          p)
            _pass=${OPTARG}
            ;;
          g)
            _group=${OPTARG}
            ;;
          c)
            _comment="${OPTARG}"
        esac
      done
      if [ $OPTIND -gt 1 ]; then
        shift $(($OPTIND -1))
        _user=${1}
      fi
      # VMware *useradd* only seems to support 16-bit UIDs. Cheat...
      if [ $vmkmaj -lt "5" ]; then
        /sbin/useradd -g ${_group} -s ${_shell} -c "${_comment}" ${_user}
      else
        # vmware 5.x throws us to the wolves.
        _gid=$(getent group ${_user}|awk -F: '{print $3}')
        echo "${_user}:x:${_uid}:${_gid}:${_comment}:/home/${_user}:/bin/ash" >> /etc/passwd
      fi
      # Change the primary group to 'root' - if you're adding accounts on ESXi
      #  via tech support mode, you probably want more admins...
      # We also 'fix' the UID at this time...
      usermod -g root -u ${_uid} -p ${_pass} -a -G ${_group} ${_user}
      # set permissions for the ESXi app as well
      /bin/vim-cmd vimsvc/auth/entity_permission_add vim.Folder:ha-folder-root ${_user} false Admin true
    }
    # usermod on ESXi does...what?
    usermod() {
      _user=
      _group=
      _pass=
      _gid=
      _grouplist=
      _append_flag=false
      _uid=
      OPTIND=1
      while getopts "g:p:G:au:" _opt; do
        case ${_opt} in
          g)
            _group=${OPTARG}
            ;;
          p)
            _pass=${OPTARG}
            ;;
          G)
            _grouplist=${OPTARG}
            ;;
          a)
            _append_flag=true
            ;;
          u)
            _uid=${OPTARG}
            ;;
        esac
      done
      if [ $OPTIND -gt 1 ]; then
        shift $(($OPTIND -1))
        _user=${1}
      fi
      pwent=$(getent passwd ${_user})
      if [ -n "${_group}" ]; then
        _gid=$(getent group ${_group}|awk 'BEGIN{FS=":"} { print $3 }') 
        npwent=$(echo "${pwent}"|awk 'BEGIN{FS=":";OFS=":"} { print $1,$2,$3,'${_gid}',$5,$6,$7 }')
        sed -e s@"${pwent}"@"${npwent}"@ /etc/passwd > /etc/passwd.new
        mv -f /etc/passwd.new /etc/passwd
      fi
      if [ -n "${_pass}" ]; then
        shent=$(getent shadow ${_user})
        if [ -z "${shent}" ] ; then
          _days=$(expr $(date '+%s') / 86400)
          echo "${_user}:${_pass}:${_days}:0:99999:7:::" >> /etc/shadow
        else
          nshent=$(echo -n "${shent}"|awk 'BEGIN{FS=":";OFS=":"} { print $1,"'${_pass}'",$3,$4,$5,$6,$7,$8,$9 }')
          sed -e s@"${shent}"@"${nshent}"@ /etc/shadow > /etc/shadow.new
          chmod u+w /etc/shadow
          mv -f /etc/shadow.new /etc/shadow
          chmod u-w /etc/shadow
        fi
      fi
      if [ -n "${_grouplist}" ]; then
        if [ ${_append_flag} == "true" ]; then
          for _group in $(echo ${_grouplist}|awk 'BEGIN{FS=","} { print }'); do
            grent=$(getent group ${_group})
            ngrent=
            grmem=$(echo -n "${grent}"|awk 'BEGIN{FS=":";} { print $4 }')
            ingroup=0
            for member in $(echo "${grmem}"|awk 'BEGIN{FS=","} { print }'); do
              if [ ${member} == ${_user} ]; then
                ingroup=1
              fi
            done
            if [ ${ingroup} == "0" ]; then
              lc=$(echo -n "${grent}"|awk '{ print substr($0,length($0),1)}')
              if [ ${lc} == ":" ]; then
                ngrent=${grent}${_user}
              else
                ngrent=${grent},${_user}
              fi
            fi
            if [ -n "${ngrent}" ]; then
              sed -e s@"${grent}"@"${ngrent}"@ /etc/group > /etc/group.new
              mv -f /etc/group.new /etc/group
            fi
          done
        fi
      fi
      if [ -n "${_uid}" ]; then
        # FIXME: refactor so write of password file is done *once*
        pwent=$(getent passwd ${_user})
        npwent=$(echo "${pwent}"|awk 'BEGIN{FS=":";OFS=":"} { print $1,$2,'${_uid}',$4,$5,$6,$7 }')
        sed -e s@"${pwent}"@"${npwent}"@ /etc/passwd > /etc/passwd.new
        mv -f /etc/passwd.new /etc/passwd
      fi
    }
  fi
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
    comment=$(awk -F ':' '{ print $5 }' ${pwent})
    # set the password hash if we have one
    if [ -f ${user}.shadow ]; then
      pass=$(awk -F ':' '{ print $2 }' ${user}.shadow)
    fi
    useradd -u ${uid} -g ${user} -p ${pass} -s ${shell} -c "${comment}" ${user}
  fi
  # Create home directories, set permissions
  userhome=$(getent passwd ${user}|awk -F ':' '{ print $6 }')
  mkdir -p "${userhome}"
  chown ${user} "${userhome}"
  pgid=$(getent passwd ${user}|awk -F ':' '{ print $4 }')
  chgrp ${pgid} "${userhome}"
  # add SSH keys if they exist
  if [ -f ${user}.pub ]; then
    # FIXME: Use sudo when available!
    #sudo -u ${user} mkdir ${userhome}/.ssh
    #echo ${user}.pub | sudo -u ${user} tee -a ${userhome}/.ssh/authorized_keys > /dev/null
    mkdir "${userhome}"/.ssh
    chown ${user} "${userhome}"/.ssh
    chgrp ${pgid} "${userhome}"/.ssh
    chmod 0700 "${userhome}"/.ssh
    cat ${user}.pub >> "${userhome}"/.ssh/authorized_keys
    chown ${user} "${userhome}"/.ssh/authorized_keys
    chgrp ${pgid} "${userhome}"/.ssh/authorized_keys
    chmod 0600 "${userhome}"/.ssh/authorized_keys
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
