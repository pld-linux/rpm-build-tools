#!/usr/bin/python3

import io
import os
import re
import sys

rep = {
    'python2': [],
    'python3': [],
    'perl': [],
}

skip_files = [".h", ".c", ".cc", ".gif", ".png", ".jpg"]

for root, dirs, files in os.walk(sys.argv[1]):
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
    files.sort()
    for i in range(0, len(files) - 1):
        print("\t%s \\\n" % files[i], end='')
    print("\t%s\n" % files[len(files) - 1])


if rep['python2']:
    print("sed -i -e '1s,#!/usr/bin/env python2,%{__python},' -e '1s,#!/usr/bin/env python,%{__python},' -e '1s,#!/usr/bin/python,%{__python},' \\")
    gf(rep['python2'])

if rep['python3']:
    print("sed -i -e '1s,#!/usr/bin/env python3,%{__python3},' \\")
    gf(rep['python3'])

if rep['perl']:
    print("sed -i -e '1s,#!/usr/bin/env perl,%{__perl},' \\")
    gf(rep['perl'])
