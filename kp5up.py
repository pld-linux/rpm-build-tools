#!/usr/bin/python2

"""
Helper script to update version of kp5*.spec.
Note that this script only set version, and set release to 1.
To update md5sum, you can call builder script.
"""

import os
import re
import sys

KP5 = '%define\t\tkdeplasmaver\t'

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print('Usage: %s specfilename version' % sys.argv[0])
        print('For example: %s ~/rpm/packages/kp5-bluedevil/kp5-bluedevil.spec 5.16.4' % sys.argv[0])
        sys.exit(1)

    spec = sys.argv[1]
    version = sys.argv[2]

    tmpspec = spec + '.tmp'
    newspec = open(tmpspec, 'w')

    with open(spec, 'r') as f:
        for line in f:
            if line.startswith(KP5):
                newspec.write("%s%s\n" % (KP5, version))
            elif line.startswith("Version:"):
                newspec.write("Version:\t%s\n" % version)
            elif line.startswith("Release:"):
                newspec.write("Release:\t1\n")
            else:
                newspec.write(line)
    newspec.close()
    os.rename(tmpspec, spec)
