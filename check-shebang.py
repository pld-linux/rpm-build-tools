#!/usr/bin/python3

# thisscript.py --root=~/tmp/somepackage ~/rpm/BUILD/somepackage/

import argparse
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
}

skip_files = [".h", ".c", ".cc", ".gif", ".png", ".jpg", ".ko", ".gz", ".o"]

if args.buildroot:
    print("%s: Caching `%s' files..." % (sys.argv[0], args.buildroot))
    rpm_build_root_files = []
    for root, dirs, files in os.walk(args.buildroot):
        for name in files:
            fname, fext = os.path.splitext(name)
            if fext in skip_files:
                continue
            rpm_build_root_files.append(fname)
    print("%s: Caching done." % (sys.argv[0]))

for root, dirs, files in os.walk(args.sourcedir):
    for name in files:
        fname, fext = os.path.splitext(name)
        if fext in skip_files:
            continue

        fpath = os.path.join(root, name)
        with open(fpath, 'rt', encoding='utf-8', errors='replace') as f:
            try:
                fline = f.read(128)
                f = io.StringIO(fline)
                shebang = f.readline()
            except UnicodeDecodeError as e:
                print("%s: skipping file `%s': %s" % (sys.argv[0], fpath, e), file=sys.stderr)
                continue
            if re.compile(r'^#!/usr/bin/env python\s').match(shebang) \
                    or re.compile(r'^#!/usr/bin/env python2\s').match(shebang) \
                    or re.compile(r'^#!/usr/bin/python\s').match(shebang):
                rep['python2'].append(fpath)
            elif re.compile(r'^#!/usr/bin/env python3\s').match(shebang):
                rep['python3'].append(fpath)
            elif re.compile(r'^#!/usr/bin/env perl\s').match(shebang):
                rep['perl'].append(fpath)

def gf(files):
    newfiles = []
    for f in files:
        if not rpm_build_root_files or os.path.basename(f) in rpm_build_root_files:
            newfiles.append(f)
    newfiles.sort()
    for i in range(0, len(newfiles) - 1):
        print("\t%s \\\n" % newfiles[i], end='')
    print("\t%s\n" % newfiles[len(newfiles) - 1])

print("\n# Copy from here:", file=sys.stderr)
print("# %s " % sys.argv[0], end='')
if args.buildroot:
    print("--root=%s " % args.buildroot, end='')
print("%s\n" % args.sourcedir)

if rep['python2']:
    print("sed -i -e '1s,#!/usr/bin/env python2,%{__python},' -e '1s,#!/usr/bin/env python,%{__python},' -e '1s,#!/usr/bin/python,%{__python},' \\")
    gf(rep['python2'])

if rep['python3']:
    print("sed -i -e '1s,#!/usr/bin/env python3,%{__python3},' \\")
    gf(rep['python3'])

if rep['perl']:
    print("sed -i -e '1s,#!/usr/bin/env perl,%{__perl},' \\")
    gf(rep['perl'])
