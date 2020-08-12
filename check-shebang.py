#!/usr/bin/python3

# thisscript.py --buildroot=~/tmp/somepackage ~/rpm/BUILD/somepackage/

import argparse
import hashlib
import io
import os
import re
import sys

parser = argparse.ArgumentParser()
parser.add_argument('sourcedir', help='RPM_SOURCE_DIR directory')
parser.add_argument("--buildroot", help="RPM_BUILD_ROOT directory")
args = parser.parse_args()

rep = {
    'python2': [],
    'python3': [],
    'perl': [],
    'ruby': [],
    'bash': [],
}

skip_files = [".h", ".c", ".cc", ".gif", ".png", ".jpg", ".ko", ".gz", ".o"]

def hash(fname):
    hash_alg = hashlib.sha256()
    with open(fname, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_alg.update(chunk)
    return hash_alg.hexdigest()

rpm_build_root_files = []
if args.buildroot:
    print("%s: Caching `%s' files..." % (sys.argv[0], args.buildroot))
    for root, dirs, files in os.walk(args.buildroot):
        for name in files:
            fname, fext = os.path.splitext(name)
            if fext in skip_files:
                continue
            fpath = os.path.join(root, name)
            try:
                rpm_build_root_files.append(hash(fpath))
            except FileNotFoundError:
                pass
    print("%s: Caching done." % (sys.argv[0]))

for root, dirs, files in os.walk(args.sourcedir):
    for name in files:
        fname, fext = os.path.splitext(name)
        if fext in skip_files:
            continue

        fpath = os.path.join(root, name)
        try:
            with open(fpath, 'rt', encoding='utf-8', errors='replace') as f:
                try:
                    fline = f.read(128)
                    f = io.StringIO(fline)
                    shebang = f.readline()
                except UnicodeDecodeError as e:
                    print("%s: skipping file `%s': %s" % (sys.argv[0], fpath, e), file=sys.stderr)
                    continue
                if re.compile(r'^#!\s*/usr/bin/env python\s').match(shebang) \
                        or re.compile(r'^#!\s*/usr/bin/env\s+python2\s').match(shebang) \
                        or re.compile(r'^#!\s*/usr/bin/python\s').match(shebang):
                    rep['python2'].append(fpath)
                elif re.compile(r'^#!\s*/usr/bin/env\s+python3\s').match(shebang):
                    rep['python3'].append(fpath)
                elif re.compile(r'^#!\s*/usr/bin/env\s+perl\s').match(shebang):
                    rep['perl'].append(fpath)
                elif re.compile(r'^#!\s*/usr/bin/env\s+ruby\s').match(shebang):
                    rep['ruby'].append(fpath)
                elif re.compile(r'^#!\s*/usr/bin/env\s+bash\s').match(shebang):
                    rep['bash'].append(fpath)
        except FileNotFoundError:
            pass

def gf(cmd, files):
    newfiles = []
    for f in files:
        if not rpm_build_root_files or hash(f) in rpm_build_root_files:
            newfiles.append(f)
    newfiles.sort()
    if not newfiles:
        return
    print(cmd)
    for i in range(0, len(newfiles) - 1):
        print("      %s \\\n" % os.path.relpath(newfiles[i], start=args.sourcedir), end='')
    print("      %s\n" % os.path.relpath(newfiles[len(newfiles) - 1], start=args.sourcedir))

print("\n# Copy from here:")
print("# %s " % sys.argv[0], end='')
if args.buildroot:
    print("--buildroot=%s " % args.buildroot, end='')
print("%s\n" % args.sourcedir)

gf("%{__sed} -E -i -e '1s,#!\s*/usr/bin/env\s+python2(\s|$),#!%{__python}\\1,' -e '1s,#!\s*/usr/bin/env\s+python(\s|$),#!%{__python}\\1,' -e '1s,#!\s*/usr/bin/python(\s|$),#!%{__python}\\1,' \\",
   rep['python2'])
gf("%{__sed} -E -i -e '1s,#!\s*/usr/bin/env\s+python3(\s|$),#!%{__python3}\\1,' \\", rep['python3'])
gf("%{__sed} -E -i -e '1s,#!\s*/usr/bin/env\s+perl(\s|$),#!%{__perl}\\1,' \\", rep['perl'])
gf("%{__sed} -E -i -e '1s,#!\s*/usr/bin/env\s+ruby(\s|$),#!%{__ruby}\\1,' \\", rep['ruby'])
gf("%{__sed} -E -i -e '1s,#!\s*/usr/bin/env\s+bash(\s|$),#!/bin/bash\\1,' \\", rep['bash'])
