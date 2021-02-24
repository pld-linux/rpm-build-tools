#!/usr/bin/python3

# rediff-patches.py name.spec

import argparse
import collections
import logging
import os
import re
import rpm
import shutil
import subprocess
import sys
import tempfile

RPMBUILD_ISPATCH = (1<<1)

def prepare_spec(r, patch_nr, before=False):
    tempspec = tempfile.NamedTemporaryFile()
    re_patch = re.compile(r'^%patch(?P<patch_number>\d+)\w*')
    for line in r.parsed.split('\n'):
        m = re_patch.match(line)
        if m:
            patch_number = int(m.group('patch_number'))
            if patch_nr == patch_number:
                if before:
                    tempspec.write(b"exit 0\n# here was patch%d\n" % patch_nr)
                else:
                    line = re.sub(r'#.*', "", line)
                    tempspec.write(b"%s\nexit 0\n" % line.encode('utf-8'))
                continue
        tempspec.write(b"%s\n" % line.encode('utf-8'))
    tempspec.flush()
    return tempspec

def unpack(spec, builddir):
    cmd = [ 'rpmbuild', '-bp',
           '--define',  '_builddir %s' % builddir,
           '--define', '_enable_debug_packages 0',
           '--define', '_default_patch_fuzz 2',
           spec ]
    logging.debug("running %s" % repr(cmd))
    subprocess.check_call(cmd, stdout=sys.stderr, stderr=sys.stderr,
                          env={'LC_ALL': 'C.UTF-8'}, timeout=600)

def diff(diffdir_org, diffdir, builddir, output):
    diffdir_org = os.path.basename(diffdir_org)
    diffdir = os.path.basename(diffdir)

    with open(output, 'wt') as f:
        cmd = [ 'diff', '-urNp', '-x', '*.orig', diffdir_org, diffdir ]
        logging.debug("running %s" % repr(cmd))
        try:
            subprocess.check_call(cmd, cwd=builddir, stdout=f, stderr=sys.stderr,
                                  env={'LC_ALL': 'C.UTF-8'}, timeout=600)
        except subprocess.CalledProcessError as err:
            if err.returncode != 1:
                raise
    logging.info("rediff generated as %s" % output)

def diffstat(patch):
    cmd = [ 'diffstat', patch ]
    logging.info("running diffstat for: %s" % patch)
    try:
        subprocess.check_call(cmd, stdout=sys.stdout, stderr=sys.stderr,
                              env={'LC_ALL': 'C.UTF-8'}, timeout=60)
    except subprocess.CalledProcessError as err:
        logging.error("running diffstat failed: %s" % err)
    except FileNotFoundError as err:
        logging.error("running diffstat failed: %s, install diffstat package?" % err)

def main():
    parser = parser = argparse.ArgumentParser(description='rediff patches to avoid fuzzy hunks')
    parser.add_argument('spec', type=str, help='spec file name')
    parser.add_argument('-p', '--patches', type=str, help='comma separated list of patch numbers to rediff')
    parser.add_argument('-v', '--verbose', help='increase output verbosity', action='store_true')
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO)
    rpm.setVerbosity(rpm.RPMLOG_ERR)

    if args.verbose:
            logging.basicConfig(level=logging.DEBUG)
            rpm.setVerbosity(rpm.RPMLOG_DEBUG)

    if args.patches:
        args.patches = [int(x) for x in args.patches.split(',')]

    specfile = args.spec

    tempdir = tempfile.TemporaryDirectory(dir="/dev/shm")
    topdir = tempdir.name
    builddir = os.path.join(topdir, 'BUILD')

    rpm.addMacro("_builddir", builddir)

    r = rpm.spec(specfile)

    patches = {}

    for (name, nr, flags) in r.sources:
        if flags & RPMBUILD_ISPATCH:
            patches[nr] = name

    applied_patches = collections.OrderedDict()
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

    for patch_nr in applied_patches.keys():
        if args.patches and patch_nr not in args.patches:
            continue
        patch_name = patches[patch_nr]
        logging.info("*** patch %d: %s" % (patch_nr, patch_name))

        tempspec = prepare_spec(r, patch_nr, before=True)
        unpack(tempspec.name, builddir)
        tempspec.close()
        os.rename(appbuilddir, appbuilddir + ".org")

        tempspec = prepare_spec(r, patch_nr, before=False)
        unpack(tempspec.name, builddir)
        tempspec.close()

        diff(appbuilddir + ".org", appbuilddir, builddir, os.path.join(topdir, os.path.join(appsourcedir, patch_name + ".rediff")))

        diffstat(os.path.join(topdir, os.path.join(appsourcedir, patch_name)))
        diffstat(os.path.join(topdir, os.path.join(appsourcedir, patch_name + ".rediff")))

        shutil.rmtree(builddir)
    tempdir.cleanup()

if __name__ == '__main__':
    main()
