#!/usr/bin/python3

# rediff-patches.py name.spec

# TODO:
# - handle rediff of last patch (need some way to terminate build just after that patch is applied)
# - or maybe apply patches on our own instead of using rpmbuild for that
# - argparse fro arguments
# - cleanup

import os
import re
import rpm
import shutil
import subprocess
import sys
import tempfile

RPMBUILD_ISPATCH = (1<<1)

def unpack(spec, builddir, until_patch=None):
    cmd = [ 'rpmbuild', '-bp', '--define',  '_builddir %s' % builddir, '--define', '_default_patch_fuzz 2' ]
    if until_patch is not None:
        cmd += [ '--define', '%%patch%d exit; #' % until_patch ]
    cmd += [ spec ]
    subprocess.check_call(cmd, stdout=sys.stderr, stderr=sys.stderr, timeout=600)

def diff(diffdir_org, diffdir, builddir, output):
    diffdir_org = os.path.basename(diffdir_org)
    diffdir = os.path.basename(diffdir)

    with open(output, 'wt') as f:
        cmd = [ 'diff', '-urNp', '-x', '*.orig', diffdir_org, diffdir ]
        try:
            subprocess.check_call(cmd, cwd=builddir, stdout=f, stderr=sys.stderr, timeout=600)
        except subprocess.CalledProcessError as err:
            if err.returncode != 1:
                raise

def main():
    specfile = sys.argv[1]

    tempdir = tempfile.TemporaryDirectory(dir="/dev/shm")
    topdir = tempdir.name
    builddir = os.path.join(topdir, 'BUILD')

    rpm.addMacro("_builddir", builddir)

    r = rpm.spec(specfile)

    patches = {}

    for (name, nr, flags) in r.sources:
        if flags & RPMBUILD_ISPATCH:
            patches[nr] = name

    applied_patches = {}
    re_patch = re.compile(r'^%patch(?P<patch_number>\d+)\w*(?P<patch_args>.*)')
    for line in r.parsed.split('\n'):
        m = re_patch.match(line)
        if not m:
            continue
        patch_nr = int(m.group('patch_number'))
        patch_args = m.group('patch_args')
        applied_patches[patch_nr] = patch_args

    appsourcedir = rpm.expandMacro("%{_sourcedir}")
    appbuilddir = rpm.expandMacro("%{_builddir}/%{?buildsubdir}")

    for (patch_nr, patch_name) in sorted(patches.items()):
        if patch_nr not in applied_patches:
            continue
        print("*** patch %d: %s" % (patch_nr, patch_name), file=sys.stderr)
        unpack(specfile, builddir, patch_nr)
        os.rename(appbuilddir, appbuilddir + ".org")
        unpack(specfile, builddir, patch_nr + 1)
        diff(appbuilddir + ".org", appbuilddir, builddir, os.path.join(topdir, os.path.join(appsourcedir, patch_name + ".rediff")))
        shutil.rmtree(builddir)
    tempdir.cleanup()

if __name__ == '__main__':
    main()
