#!/usr/bin/python

"""
Helper script to update version of kf5*.spec.
Note that this script only set version, and set release to 1.
To update md5sum, you can call builder script.
"""

import os
import re
import sys

def get_framework_version(version):
    v = version.split('.')
    return v[0] + '.' + v[1]

FRAMEWORK = '%define\t\tkdeframever\t'

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print('Usage: %s kf5specfilename version' % sys.argv[0])
        print('For example: %s ~/rpm/packages/kf5-extra-cmake-modules/kf5-extra-cmake-modules.spec 5.57.0' % sys.argv[0])
        sys.exit(1)
    spec = sys.argv[1]
    version = sys.argv[2]
    kfver = get_framework_version(version)
    tmpspecname = spec + '.tmp'
    newspec = open(tmpspecname, 'w')

    with open(spec, 'r') as f:
        for line in f:
            if line.startswith(FRAMEWORK):
                newspec.write("%s%s\n" % (FRAMEWORK, kfver))
            elif line.startswith("Version:"):
                newspec.write("Version:\t%s\n" % version)
            elif line.startswith("Release:"):
                newspec.write("Release:\t1\n")
            else:
                newspec.write(line)
    newspec.close()
    os.rename(tmpspecname, spec)
