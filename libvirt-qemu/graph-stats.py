#!/usr/bin/python
# Original code by Jerome Petazzoni <jp at enix dot org>
# with a useful patch by Markus Dorn <markus dot dorn at gmail dot com>
import sys
import os
import glob
import time

if len(sys.argv)!=2:
    print "Syntax: %s <rrdbasename>"%sys.argv[0]
    sys.exit(1)

colors=["000000", "FF0000", "00FF00", "0000FF" ]
colors+=["DEDE00", "00FFFF", "FF90FF", "FF8040", "C040A0", "A0A0A0", "40A0A0", "40A0FF", "FFA040" ]

def graph(basename, subname, seconds):
    rrds=glob.glob(basename+"*.rrd")
    rrds=[x for x in rrds if os.stat(x)[8] > (time.time()-seconds)]

    cmdline="--imgformat PNG --vertical-label CPU%"

    if seconds>800000: lastoraverage="AVERAGE"
    else: lastoraverage="LAST"
 	
    for rrd,id in zip(rrds,range(len(rrds))):
	cmdline+="DEF:id%draw=%s:cpu:%s "%(id,rrd,lastoraverage)
	cmdline+="CDEF:id%dpercent=id%draw,10,/ "%(id,id)
	cmdline+="CDEF:id%dzero=id%dpercent,DUP,UN,EXC,0,EXC,IF "%(id,id)
    for rrd,id in zip(rrds,range(len(rrds))):
	cmdline+="%s:id%dzero#%s:%s "%({0:"AREA"}.get(id,"STACK"),id,colors[id%len(colors)],rrd[len(basename):-4])
	cmdline+="GPRINT:id%dpercent:AVERAGE:\"%s\" "%(id,"Average CPU usage\: %02.0lf%%\\j")

    os.system("rrdtool graph %s%s.png --start -%d --end -69 %s"%("/var/www/mrtg/libvirt/",subname,seconds,cmdline))

basename=sys.argv[1]
graph(basename, "hourly", 4000)
graph(basename, "daily", 100000)
graph(basename, "weekly", 800000)
graph(basename, "monthly", 3200000)
graph(basename, "yearly", 40000000)

