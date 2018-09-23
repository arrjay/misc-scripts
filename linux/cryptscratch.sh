#!/usr/bin/env bash

set -ue

# script to wipe/format/mount luks volume
shopt -s nullglob

force_overwrite="${DOIT:-no}"
fsmount="${FS_MOUNTDIR:-/mnt/volatile}"
mkswap="${CREATE_SWAP:-yes}"
fsdev="${DEVICE:-}"

wipeall () {
  local disk part
  disk="${1}"
  for part in "${disk}"[0-9]* ; do
    wipefs -a "${part}"
  done
  wipefs -a "${disk}"
}

partition () {
  local disk fsp_start
  disk="${1}"
  parted -s "${disk}" mklabel gpt
  case "${mkswap}" in
    yes) parted "${disk}" mkpart swap 1m 100m ; fsp_start=101m ;;
    *) fsp_start=1m ;;
  esac
  parted "${disk}" mkpart volatile "${fsp_start}" 100%
  sleep 1
}

random_setup () {
  local disk basedisk part ct
  disk="${1}" ; basedisk="${disk##*/}" ; ct=1
  for part in "${disk}"[0-9]* ; do
    cryptsetup create --key-file=/dev/urandom "crypt-${basedisk}-${ct}" "${part}"
    ((ct++))
  done
  echo "crypt-${basedisk}-"
}

filesystems () {
  local base part lastpart mountpt
  base="${1}" ; mountpt="${2}"
  # find last partition to create as filesystem
  for part in "/dev/mapper/${base}"[0-9]* ; do
    lastpart="${part}"
  done
  # format, mount
  mkfs.ext4 "${lastpart}"
  mkdir -p "${mountpt}"
  mount "${lastpart}" "${mountpt}"
  # if the last partition is not the first partition, format the first partition as swap and activate it, deactivating other swaps
  [ "${lastpart}" != "/dev/mapper/${base}-1" ] && {
    mkswap "/dev/mapper/${base}1"
    swapoff -a
    swapon "/dev/mapper/${base}1"
  }
}

files () {
  local mountpt
  mountpt="${1}"
  # create replacement /tmp
  mkdir -p "${mountpt}/tmp"
  chown root:root "${mountpt}/tmp"
  chmod 1777 "${mountpt}/tmp"
  mount -o bind "${mountpt}/tmp" "/tmp"
  # create potential /home
  mkdir -p "${mountpt}/home"
  chown root:root "${mountpt}/home"
  chmod 755 "${mountpt}/home"
}

[ "${fsdev}" ] || { printf 'need to supply DEVICE envvar\n' 1>&2 ; exit 1 ; }
[ "${force_overwrite}" == "YES" ] || { printf 'need to supply envvar to run script ;)\n' 1>&2 ; exit 1 ; }

wipeall "${fsdev}"
partition "${fsdev}"
basedev=$(random_setup "${fsdev}")
filesystems "${basedev}" "${fsmount}"
files "${fsmount}"
