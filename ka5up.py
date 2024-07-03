#!/usr/bin/python2

"""
Helper script to update version of ka5*.spec.
Note that this script only set version, and set release to 1.
To update md5sum, you can call builder script.
"""

import os
import re
import sys

APP = '%define\t\tkdeappsver\t'

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print('Usage: %s specfilename version' % sys.argv[0])
        print('For example: %s ~/rpm/packages/ka5-konsole/ka5-konsole.spec 19.04.1' % sys.argv[0])
        sys.exit(1)

    spec = sys.argv[1]
    version = sys.argv[2]

    tmpspec = spec + '.tmp'
    newspec = open(tmpspec, 'w')

    with open(spec, 'r') as f:
        for line in f:
            if line.startswith(APP):
                newspec.write("%s%s\n" % (APP, version))
            elif line.startswith("Version:"):
                newspec.write("Version:\t%s\n" % version)
            elif line.startswith("Release:"):
                newspec.write("Release:\t1\n")
            else:
                newspec.write(line)
    newspec.close()
    os.rename(tmpspec, spec)
