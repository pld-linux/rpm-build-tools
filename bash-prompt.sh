# NOTE:
# This code is known to work with bash

# the code below requires bash 4.x, skip if earlier
test ${BASH_VERSION%%.*} -lt 4 && return 1

# To use it, source this file and set $PROMPT_COMMAND env var:
# PROMPT_COMMAND=__bash_prompt_command

#
# A colorized bash prompt
# - shows current branch
# - shows if branch is up to date/ahead/behind
# - shows if last command exited with error (red)
#
__bash_prompt_command() {
	local previous_return_value=$?

	local RED="\[\033[0;31m\]"
	local YELLOW="\[\033[0;33m\]"
	local GREEN="\[\033[0;32m\]"
	local BLUE="\[\033[0;34m\]"
	local LIGHT_RED="\[\033[1;31m\]"
	local LIGHT_GREEN="\[\033[1;32m\]"
	local WHITE="\[\033[1;37m\]"
	local LIGHT_GRAY="\[\033[0;37m\]"
	local COLOR_NONE="\[\e[0m\]"

	# if we are in rpm subdir and have exactly one .spec in the dir, include package version
	__package_update_rpmversion
	local rpmver=$(__package_rpmversion)

	local prompt="${BLUE}[${RED}\w${GREEN}${rpmver:+($rpmver)}$(__bash_parse_git_branch)${BLUE}]${COLOR_NONE} "
	if [ $previous_return_value -eq 0 ]; then
		PS1="${prompt}➔ "
	else
		PS1="${prompt}${RED}➔${COLOR_NONE} "
	fi
}

# helper for __bash_prompt_command
# command line (git) coloring
# note we use "\" here to avoid any "git" previous alias/func
__bash_parse_git_branch() {
	# not in git dir. return early
	git rev-parse --git-dir &> /dev/null || return

	local state remote branch

	# without branch, nothing is shown; don't bother further
	branch=$(git symbolic-ref --short HEAD 2>/dev/null) || return

	if [ -n "$(git status -s 2> /dev/null)" ]; then
		state="${RED}★"
	fi

	# http://stackoverflow.com/a/3278427
	remote=$(git rev-parse '@{u}' 2>/dev/null)
	if [[ -n "$remote" ]]; then
		local=$(git rev-parse @)
		base=$(git merge-base @ '@{u}')

		if [[ $local = $remote ]]; then
			remote=""
		elif [[ $local = $base ]]; then
			remote="${YELLOW}↓"
		elif [[ $remote = $base ]]; then
			remote="${YELLOW}↑"
		else
			remote="${YELLOW}↕"
		fi
	fi

	echo " (${branch})${remote}${state}"
}

# cache requires bash 4.x
declare -A __package_update_rpmversion_cache=()
__package_update_rpmversion() {
	# extract vars from cache
	set -- ${__package_update_rpmversion_cache[$PWD]}
	local specfile=$1 version=$2 mtime=$3

	# invalidate cache
	if [ -f "$specfile" ]; then
		local stat
		stat=$(stat -c %Y $specfile)
		if [ $mtime ] && [ $stat -gt $mtime ]; then
			unset version
		fi
		mtime=$stat
	else
		# reset cache, .spec may be renamed
		unset version specfile
	fi

	# we have cached version
	test -n "$version" && return

	# needs to be one file
	specfile=${specfile:-$(\ls *.spec 2>/dev/null)}
	if [ ! -f "$specfile" ]; then
		unset __package_update_rpmversion_cache[$PWD]
		return
	fi

	mtime=${mtime:-$(stat -c %Y $specfile)}

	# give only first version (ignore subpackages)
	version=$(rpm --define "_specdir $PWD" --specfile $specfile -q --qf '%{VERSION}\n' | head -n1)
	__package_update_rpmversion_cache[$PWD]="$specfile ${version:-ERR} $mtime"
}

__package_rpmversion() {
	# extract vars from cache
	set -- ${__package_update_rpmversion_cache[$PWD]}
	# print version
	echo $2
}
