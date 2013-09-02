#!/bin/bash

esnsi=/etc/sysconfig/network-scripts/ifcfg-

ifmove () {
  old=$1
  new=$2
  sedexp=s/${old}/${new}/g
  sed -e "$sedexp" -i /etc/udev/rules.d/70-persistent-net.rules
  mv ${esnsi}${old} ${esnsi}${new}
  sed -e "$sedexp" -i ${esnsi}${new}
}

if_cfgnone() {
  if=$1
  sed -e 's/BOOTPROTO="dhcp"/BOOTPROTO="none"/' -i ${esnsi}${if}
  sed -e 's/BOOTPROTO="static"/BOOTPROTO="none"/' -i ${esnsi}${if}
  sed -e 's/ONBOOT="no"/ONBOOT="yes"/' -i ${esnsi}${if}
  echo 'IPV6_AUTOCONF="no"' >> ${esnsi}${if}
}

if_addbr() {
  br=$1
  if=$2
  cat>${esnsi}${br}<<EOF
DEVICE=${br}
TYPE=Bridge
ONBOOT=yes
BOOTPROTO=none
IPV6INIT=no
IPV6_AUTOCONF=no
DELAY=0
STP=off
EOF
  if [ -n "${if}" ]; then
    echo "BRIDGE=${br}" >> ${esnsi}${if}
  fi
}

stab_nm() {
  # NOTE: uses old if names!
  for x in ${esnsi}eth* ; do sed -e 's/NM_CONTROLLED="yes"/NM_CONTROLLED="no"/g' -i $x ; done
}

stab_ipv6() {
  echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
}

$@
