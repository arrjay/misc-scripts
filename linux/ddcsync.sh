#!/usr/bin/env bash

# quick hack to glue ddcutil to udev events so I can switch monitor inputs when the keyboard shows up
# # we explicitly enumerate all the buses to hand over bus ids to ddcutil. operations through MST are *weird*
get_monitor_bus () {
  local model="${1}"
  local line
  while read -r line ; do
  case "${line}" in
    *"  ${model}") echo "${line%  *}" ;;
  esac
  done < <(awk '$1 == "I2C" { split($3,p,"-");b=p[2] } $1 == "Model:" { $1="";m=$0 } $1 == "VCP" { printf "%s %s\n",b,m }' < "${cache}")
}

do_monitor () {
  local model="${1}"
  local value="${2}"
  ddcutil --bus "$(get_monitor_bus "${model}")" setvcp 60 "${value}" &
}

# cache is a global variable.
# ddcpid is a global variable.
populate_cache () {
  [[ "${cache}" ]] || cache="$(mktemp /dev/shm/ddcsync.XXXXXX)"
  [[ "${ddcpid}" ]] || ddcutil detect > "${cache}" & ddcpid=$!
  while ! [[ -s "${cache}" ]] ; do
    sleep 0.1
  done
}

_atexit () {
  [[ "${cache}" ]] && { rm "${cache}" ; }
}
trap _atexit EXIT

for bin in ddcutil awk hostname mktemp ; do
  type "${bin}" >/dev/null 2>&1 || exit 1
done

case "$(hostname)" in
  baler-lx)
    populate_cache
    do_monitor "DELL U3419W" 0x11 # HDMI-1
    do_monitor "DELL U2715H" 0x11 # HDMI-1
  ;;
  lintendo64)
    populate_cache
    do_monitor "DELL U3419W" 0x1b # USB-C
    do_monitor "DELL U2715H" 0x10 # DisplayPort-2
  ;;
  u12345f5f858651*)
    populate_cache
    do_monitor "DELL U3491W" 0x0f # DisplayPort-1
    do_monitor "DELL U2715H" 0x0f # DisplayPort-1
  ;;
esac

# wait for those backgrounded
while wait -n ; do : ; done
