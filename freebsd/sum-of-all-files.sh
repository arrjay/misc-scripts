#!/usr/bin/env bash

ZPOOLS="datapool"
OUTDIR="/root"

for mount in $(zfs list -r ${ZPOOLS} | grep -v MOUNTPOINT | grep -v backups | awk '{ print $5 }') ; do
  OUTFILE="${OUTDIR}/$(echo ${mount} | sed -e 's@/@@' -e 's@/@-@g')"
  find -x ${mount} -type f -exec gmd5sum '{}' \; > ${OUTFILE}
done
