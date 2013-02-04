#!/bin/sh

if [ $(whoami) != "root" ]; then
  echo "this script needs to be run as root to modify accounts"
fi

# declare overrides if needed
if [ $(uname -s) == "VMkernel" ]; then
  vmkmaj=$(uname -r|sed s'/\..*//')
  if [ $vmkmaj -lt "5" ]; then
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
      shift $(($OPTIND -1))
      _user=${1}
      /sbin/useradd -u ${_uid} -g ${_group} -s ${_shell} -c "${_comment}" ${_user}
      usermod -g root -p ${_pass} ${_user}
    }
    # usermod on ESXi does...what?
    usermod() {
      _user=
      _group=
      _pass=
      _gid=
      OPTIND=1
      while getopts "g:p:" _opt; do
        case ${_opt} in
          g)
            _group=${OPTARG}
            ;;
          p)
            _pass=${OPTARG}
            ;;
        esac
      done
      shift $(($OPTIND -1))
      _user=${1}
      pwent=$(getent passwd ${_user})
      if [ -n "${_group}" ]; then
        _gid=$(getent group ${_group}|awk 'BEGIN{FS=":"} { print $3 }') 
        npwent=$(echo "${pwent}"|awk 'BEGIN{FS=":";OFS=":"} { print $1,$2,$3,'${_gid}',$5,$6,$7 }')
        sed -e s@"${pwent}"@"${npwent}"@ /etc/passwd > /etc/passwd.new
        mv -f /etc/passwd.new /etc/passwd
      fi
      if [ -n "${_pass}" ]; then
        shent=$(getent shadow ${_user})
        nshent=$(echo -n "${shent}"|awk 'BEGIN{FS=":",OFS=":"} { print $1,"'${_pass}'",$3,$4,$5,$6,$7,$8,$9 }')
        sed -e s@"${shent}"@"${nshent}"@ /etc/shadow > /etc/shadow.new
        chmod u+w /etc/shadow
        mv -f /etc/shadow.new /etc/shadow
        chmod u-w /etc/shadow
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
