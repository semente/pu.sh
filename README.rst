pu.sh
=====

**pu.sh** is a simple POSIX shell script which deploys a nice
versioned backup solution based on rsync's hardlinking capability,
which creates many snapshots in local or remote hosts (with SSH)
without data redundancy.

**Project website:**
    https://bitbucket.org/semente/pu.sh/

**Why not rsnapshot?**

*rsnapshot* is infinitely better than pu.sh, but works
differently. Whereas rsnapshot download, pu.sh upload.

rsnapshot pulls, pu.sh pushes. Remember that! :)


Install instructions
--------------------

It's simple, just copy the file ``pu.sh`` to some directory in your
``PATH`` and give it *execute* permission.

Running
-------

To run ``pu.sh`` you must have these softwares installed in your
computer:

* rsync;
* OpenSSH client (ssh), if you need push backups to a remote host.

**Synopsys**::

   $ pu.sh [-q] [-v]... [-e FILE] [-l FILE] [--] SRC [SRC]... [[USER@]HOST:]DEST

Usage examples
--------------

Backup some dirs into /var/backups::

   $ pu.sh /home /usr/local/bin /var/backups

Backup / with a exclude list into /backups on example.net::

   # pu.sh -e /etc/pu-sh/exclude.list / root@example.net:/backups/

Backup /var/mail to remote host and writes a log in /var/log/pu-sh.log::

   # pu.sh -l /var/log/pu-sh.log /var/mail root@192.168.0.1:/var/cache/pu-sh

For more instructions, run ``pu.sh -h``.

Simple deploy
-------------

Put the script below to be ran by *cron*::

   #!/bin/sh
   SOURCES="/etc /srv /opt /home /root /var/lib /var/www /usr/local /var/log /var/mail /var/spool"
   DEST="user@example.net:/backups/`hostname -f`"

   cat <<END_EXCLUDE_LIST | /usr/local/bin/pu.sh -q -l /var/log/pu-sh.log $SOURCES $DEST
   lost+found/
   *~
   .nfs*
   /media
   /mnt
   /dev
   /proc
   /sys
   /tmp
   /var/tmp
   END_EXCLUDE_LIST

On destination directory, you gonna get something like this::

   2008-02-22_21:17:02/    2008-02-23_01:17:02/    2008-02-23_05:17:02/
   2008-02-22_22:17:02/    2008-02-23_02:17:02/    2008-02-23_06:17:02/
   2008-02-23_10:17:02/    last@

License information
-------------------

Copyright (C) 2008, 2009 Guilherme Gondim <semente@taurinus.org>

pu.sh is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

pu.sh is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
License for more details.

You should have received a copy of the GNU General Public License
along with this program; see the file COPYING.  If not, see
<http://www.gnu.org/licenses/>.
