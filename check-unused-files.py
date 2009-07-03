#!/usr/bin/python

import subprocess
import sys
import os

if len(sys.argv) != 2:
    print >> sys.stderr, "Usage: %s <spec>" % sys.argv[0]
    sys.exit(1)

spec = sys.argv[1]

if not os.path.isfile(spec):
    print >> sys.stderr, "%s: %s doesn't exist!" % (sys.argv[0], spec)
    sys.exit(1)

dir = os.path.dirname(spec)
if dir == '':
    dir = '.'

p = subprocess.Popen(['rpm-specdump', spec], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
(out, err) = p.communicate(None)
p.wait()

files = []

for l in out.split('\n'):
    data = l.split()
    if len(data) != 3 or data[0] != 's':
        continue
    file = os.path.basename(data[2])
    files.append(file)

obsolete = []

for file in os.listdir(dir):
    file = os.path.basename(file)
    if file in [ '.', '..', 'CVS', '.cvsignore', 'dropin', 'md5', 'adapter', 'builder', 'relup.sh', 'compile.sh', 'repackage.sh', spec ]:
        continue
    if file not in files:
        print "Obsolete file: %s" % file
        obsolete.append(file)

print
print "cvs rm -f %s" % " ".join(obsolete)



