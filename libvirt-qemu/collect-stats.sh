#!/bin/bash

# directory where RRDs are stored
RRDDIR=/var/lib/mrtg/virsh/

# Script expects to be run every 5 minutes
STEP="300"
# requires: RRDTool

# RRDTool parameters
DSDEF="DS:cpu:COUNTER:600:0:18446744073709551615"
# 10 days of exact archive
RRA_5MIN="RRA:LAST:0.5:1:15000"
# 42 days of 1 hour RRD
RRA_1H="RRA:MIN:0.5:60:1000 RRA:MAX:0.5:60:1000 RRA:AVERAGE:0.5:60:1000"
# 1000 days of 1 day RRD
RRA_1D="RRA:MIN:0.5:1440:1000 RRA:MAX:0.5:1440:1000 RRA:AVERAGE:0.5:1440:1000"

domlist=$(virsh list --all | sed -e '/-.*-/d' -e '/.*Id.*Name.*State.*/d' -e '/^$/d' | awk '{ print $2 }')

for domain in $domlist ; do
  rrd=${RRDDIR}${domain}.rrd
  cpums=$(virsh dominfo $domain | grep "CPU time:" | awk '{ print $3 }' | sed -e 's/s//' -e 's/\.//')
  if [ -z ${cpums} ]; then
    cpums=0
  fi
  if [ ! -f ${rrd} ] ; then
    rrdtool create ${rrd} --step ${STEP} ${DSDEF} ${RRA_5MIN} ${RRA_1H} ${RRA_1D}
  fi
  rrdtool update ${rrd} N:${cpums}
done
