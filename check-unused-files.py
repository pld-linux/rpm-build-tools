#!/usr/bin/python2

import subprocess
import sys
import os
import fnmatch

def filterout_warnings(err, separator="\n"):
    def filter():
        for line in err.split(separator):
            if line.startswith("warning: "):
                continue
            yield line

    return separator.join(list(filter()))

def specdump(spec):
    p = subprocess.Popen(['rpm-specdump', spec], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (out, err) = p.communicate(None)
    p.wait()

    err = filterout_warnings(err)

    return (out, err)

if len(sys.argv) == 2:
    spec = sys.argv[1]
else:
    # try autodetecting
    spec = "%s.spec" % os.path.basename(os.getcwd())

if not os.path.isfile(spec):
    print >> sys.stderr, "%s: %s doesn't exist!" % (sys.argv[0], spec)
    sys.exit(1)

dir = os.path.dirname(spec)
if dir == '':
    dir = '.'

(out, err) = specdump(spec)
if err:
    print >> sys.stderr, "%s: %s" % (sys.argv[0], err)
    sys.exit(1)

files = []

for l in out.split('\n'):
    data = l.split()
    if len(data) != 3 or data[0] != 's':
        continue
    file = os.path.basename(data[2])
    files.append(file)

obsolete = []

# files to exclude
exclude = ['log.*', '.#*', '*~', '*.orig', '*.sw?', '.bigfiles', 'sources']

# read .gitignore, distfiles files are filled there
if os.path.isfile('%s/.gitignore' % dir):
    f = open('%s/.gitignore' % dir , 'r')
    for l in f.readlines():
        exclude.append(l.rstrip())

def git_entries(file):
    p = subprocess.Popen(['git', 'ls-files'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (out, err) = p.communicate(None)
    p.wait()
    if err:
        print >> sys.stderr, "%s: %s" % (sys.argv[0], err)
        sys.exit(1)
    return out.split('\n')
gitfiles = git_entries(dir)

def blacklisted(file):
    if file == os.path.basename(spec):
        return True

    if file in [ '.', '..', '.git', 'CVS', 'TODO']:
        return True

    if os.path.isdir(file):
        return True

    for pat in exclude:
        if fnmatch.fnmatch(file, pat):
            return True

    return False

for file in os.listdir(dir):
    file = os.path.basename(file)
    if blacklisted(file):
        continue

    if not file in gitfiles:
        print "Not in repo: %s" % file
        continue

    if file not in files:
        print "Obsolete file: %s" % file
        obsolete.append(file)

if obsolete:
    print
    print "git rm %s" % " ".join(obsolete)
    print "git commit -m '- drop obsolete files' %s" % " ".join(obsolete)
