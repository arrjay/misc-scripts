#!/bin/sh

# get iso volume label
#vol_label=$(isoinfo -d -i "${1}" | grep 'Volume id'|awk -F': ' '{print $2}')
# rename iso to volume label
#mv -i "${1}" "${vol_label}.iso"

# save a sum
gsha512sum "${1}" >> SHA512SUMS

# create temporary directory for loopback use
mountpoint=$(mktemp -d)

# create md device
mountdev=$(mdconfig -a -t vnode "${1}")

# mount
mount_cd9660 /dev/${mountdev} ${mountpoint}

# create staging directory
stage=$(echo ${1}|sed 's/\..*$//')
mkdir "${stage}"

# populate
cp -R ${mountpoint}/ "${stage}"/

# call jigdo
jigdo-file make-template -i "${1}" -t "${stage}.template" -j "${stage}.jigdo" "${stage}"

# unmount
umount ${mountpoint}

# delete md device
mdconfig -d -u ${mountdev}

# delete mountdir
rmdir ${mountpoint}
