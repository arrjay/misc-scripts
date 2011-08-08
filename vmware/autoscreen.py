#!/usr/bin/env python

import os, sys, re
from pyinotify import WatchManager, Notifier, ProcessEvent, EventsCodes
import pyinotify

# redirect output to...what?
if (hasattr(os, "devnull")):
    REDIRECT_TO = os.devnull
else:
    REDIRECT_TO = "/dev/null"

# path to watch for vmware bits
path = '/srv/vmware/.vmserial/'

# path to create ptys in
ptypath = '/srv/vmware/.vmpty/'

def CreateDaemon():
    # attempt to fork out
    try:
        pid = os.fork()
    except OSError, e:
        raise Exception, "%s [%d]" % (e.strerror, e.errno)

    # first child
    if (pid == 0):
        # obtain session lead
        os.setsid()

        try:
            # create a second child
            pid = os.fork()
        except OsError, e:
            raise Exception, "%s [%d]" % (e.strerror, e.errno)

        if (pid == 0):  # in the second child
            # set working directory
            os.chdir("/root")

            # start a screen handler
            os.system("screen -U -d -m -S vmware -t `uname -n` /bin/bash -i")

            # monitor the directory
            Monitor(path)

        else:
            os._exit(0) # reap the child
    else:
        os._exit(0) # exit the parent

def Monitor(path):
    class PCreate(ProcessEvent):
        def process_IN_CREATE(self, event):
            f = event.name and os.path.join(event.path, event.name) or event.path
            # remove path element from entity
            item = f[len(path):]

            # start a socat instance
            socat_cmd = "socat "
            socat_cmd += path
            socat_cmd += item
            socat_cmd += " pty:,link="
            socat_cmd += ptypath
            socat_cmd += item
            socat_cmd += " &"
            os.system(socat_cmd)
            # load in a screen session
            screen_cmd = "screen -S vmware -X eval 'screen -t "
            screen_cmd += item
            screen_cmd += " -L "
            screen_cmd += ptypath
            screen_cmd += item
            screen_cmd += " 9600'"
            os.system(screen_cmd)

    wm = WatchManager()
    notifier = Notifier(wm, PCreate())
    wm.add_watch(path, pyinotify.IN_CREATE)

    try:
        while 1:
            notifier.process_events()
            if notifier.check_events():
                notifier.read_events()
    except KeyboardInterrupt:
        notifier.stop()
        return

if __name__ == '__main__':
    # daemonize
    CreateDaemon()
