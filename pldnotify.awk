#!/bin/awk -f
# $Revision$, $Date$
#
# Copyright (C) 2000-2010 PLD-Team <feedback@pld-linux.org>
# Authors:
#	Sebastian Zagrodzki <zagrodzki@pld-linux.org>
#	Jacek Konieczny <jajcus@pld-linux.org>
#	Andrzej Krzysztofowicz <ankry@pld-linux.org>
#	Jakub Bogusz <qboosh@pld-linux.org>
#	Elan Ruusamäe <glen@pld-linux.org>
#
# See cvs log pldnotify.awk for list of contributors
#
# TODO:
# - "SourceXDownload" support (use given URLs if present instead of cut-down SourceX URLs)
# - "SourceXActiveFTP" support


function d(s) {
	if (!DEBUG) {
		return
	}
	print s >> "/dev/stderr"
}

function fixedsub(s1,s2,t,	ind) {
# substitutes fixed strings (not regexps)
	if (ind = index(t,s1)) {
		t = substr(t, 1, ind-1) s2 substr(t, ind+length(s1))
	}
	return t
}

function ispre(s) {
	if ((s~"pre")||(s~"PRE")||(s~"beta")||(s~"BETA")||(s~"alpha")||(s~"ALPHA")||(s~"rc")||(s~"RC")) {
		d("pre-version")
		return 1
	} else {
		return 0
	}
}

function compare_ver(v1,v2) {
# compares version numbers
	while (match(v1,/[a-zA-Z][0-9]|[0-9][a-zA-Z]/))
		v1=(substr(v1,1,RSTART) "." substr(v1,RSTART+RLENGTH-1))
	while (match(v2,/[a-zA-Z][0-9]|[0-9][a-zA-Z]/))
		v2=(substr(v2,1,RSTART) "." substr(v2,RSTART+RLENGTH-1))
	sub("^0*","",v1)
	sub("^0*","",v2)
	gsub("\.0*",".",v1)
	gsub("\.0*",".",v2)
	d("v1 == " v1)
	d("v2 == " v2)
	count=split(v1,v1a,"\.")
	count2=split(v2,v2a,"\.")

	if (count<count2) mincount=count
	else mincount=count2

	for (i=1; i<=mincount; i++) {
		if (v1a[i]=="") v1a[i]=0
		if (v2a[i]=="") v2a[i]=0
		d("i == " i)
		d("v1[i] == " v1a[i])
		d("v2[i] == " v2a[i])
		if ((v1a[i]~/[0-9]/)&&(v2a[i]~/[0-9]/)) {
			if (length(v2a[i])>length(v1a[i]))
				return 1
			else if (v2a[i]>v1a[i])
				return 1
			else if (length(v1a[i])>length(v2a[i]))
				return 0
			else if (v1a[i]>v2a[i])
				return 0
		} else if ((v1a[i]~/[A-Za-z]/)&&(v2a[i]~/[A-Za-z]/)) {
			if (v2a[i]>v1a[i])
				return 1
			else if (v1a[i]>v2a[i])
				return 0
		} else if (ispre(v1a[i]) == 1)
			return 1
		else
			return 0
	}
	if ((count2==mincount)&&(count!=count2)) {
		for (i=count2+1; i<=count; i++)
			if (ispre(v1a[i]) == 1)
				return 1
		return 0
	} else if (count!=count2) {
		for (i=count+1; i<=count2; i++)
			if (ispre(v2a[i]) == 1)
				return 0
		return 1
	}
	return 0
}

function compare_ver_dec(v1,v2) {
# compares version numbers as decimal floats
	while (match(v1,/[0-9][a-zA-Z]/))
		v1=(substr(v1,1,RSTART) "." substr(v1,RSTART+RLENGTH-1))
	while (match(v2,/[0-9][a-zA-Z]/))
		v2=(substr(v2,1,RSTART) "." substr(v2,RSTART+RLENGTH-1))
	sub("^0*","",v1)
	sub("^0*","",v2)
	d("v1 == " v1)
	d("v2 == " v2)
	count=split(v1,v1a,"\.")
	count2=split(v2,v2a,"\.")

	if (count<count2) mincount=count
	else mincount=count2

	for (i=1; i<=mincount; i++) {
		if (v1a[i]=="") v1a[i]=0
		if (v2a[i]=="") v2a[i]=0
		d("i == " i)
		d("v1[i] == " v1a[i])
		d("v2[i] == " v2a[i])
		if ((v1a[i]~/[0-9]/)&&(v2a[i]~/[0-9]/)) {
			if (i==2) {
				if (0+("." v2a[i])>0+("." v1a[i]))
					return 1
				else if (0+("." v1a[i])>0+("." v2a[i]))
					return 0
			} else {
				if (length(v2a[i])>length(v1a[i]))
					return 1
				else if (v2a[i]>v1a[i])
					return 1
				else if (length(v1a[i])>length(v2a[i]))
					return 0
				else if (v1a[i]>v2a[i])
					return 0
			}
		} else if ((v1a[i]~/[A-Za-z]/)&&(v2a[i]~/[A-Za-z]/)) {
			if (v2a[i]>v1a[i])
				return 1
			else if (v1a[i]>v2a[i])
				return 0
		} else if (ispre(v1a[i]) == 1)
			return 1
		else
			return 0
	}
	if ((count2==mincount)&&(count!=count2)) {
		for (i=count2+1; i<=count; i++)
			if (ispre(v1a[i]) == 1)
				return 1
		return 0
	} else if (count!=count2) {
		for (i=count+1; i<=count2; i++)
			if (ispre(v2a[i]) == 1)
				return 0
		return 1
	}
	return 0
}

function link_seen(link) {
	for (seenlink in frameseen) {
		if (seenlink == link) {
			d("Link: [" link "] seen already, skipping...")
			return 1
		}
	}
	frameseen[link]=1
	return 0
}

function mktemp(   _cmd, _tmpfile) {
	_cmd = "mktemp /tmp/XXXXXX"
	_cmd | getline _tmpfile
	close(_cmd)
	return _tmpfile
}

# fix link to artificial one that will be recognized rest of this script
function postfix_link(url, link) {
	oldlink = link
	if ((url ~/^(http|https):\/\/github.com\//) && (link ~ /.*\/tarball\//)) {
		gsub(".*\/tarball\/", "", link)
		link = link ".tar.gz"
	}
	d("POST FIXING URL [ " oldlink " ] to [ " link " ]")
	return link
}

# get all <A HREF=..> tags from specified URL
function get_links(url,filename,   errno,link,oneline,retval,odp,wholeodp,lowerodp,tmpfile,cmd) {

	wholeerr=""

	tmpfile = mktemp()
	tmpfileerr = mktemp()

	if (url ~ /^http:\/\/(download|dl).(sf|sourceforge).net\//) {
		gsub("^http://(download|dl).(sf|sourceforge).net/", "", url)
		gsub("/.*", "", url)
		url = "http://sourceforge.net/projects/" url "/files/"
		d("sf url, mungled url to: " url)
	}

	if (url ~ /^http:\/\/(.*)\.googlecode\.com\/files\//) {
		gsub("^http://", "", url)
		gsub("\..*", "", url)
		url = "http://code.google.com/p/" url "/downloads/list"
		d("googlecode url, mungled url to: " url)
	}

	if (url ~ /^http:\/\/pecl.php.net\/get\//) {
		gsub("-.*", "", filename)
		url = "http://pecl.php.net/package/" filename
		d("pecl.php.net url, mungled url to: " url)
	}

	if (url ~ /^(http|ftp):\/\/mysql.*\/Downloads\/MySQL-5.1\//) {
		url = "http://dev.mysql.com/downloads/mysql/5.1.html#source"
		 d("mysql 5.1 url, mungled url to: " url)
	}

	if (url ~/^(http|https):\/\/launchpad\.net\/(.*)\//) {
		gsub("^(http|https):\/\/launchpad\.net\/", "", url)
		gsub("\/.*/", "", url)
		url = "https://code.launchpad.net/" url "/+download"
		d("main launchpad url, mungled url to: " url)
	}

	if (url ~/^(http|https):\/\/edge\.launchpad\.net\/(.*)\//) {
		gsub("^(http|https):\/\/edge\.launchpad\.net\/", "", url)
		gsub("\/.*/", "", url)
		url = "https://edge.launchpad.net/" url "/+download"
		d("edge launchpad url, mungled url to: " url)
	}

	if (url ~/^(http|https):\/\/github.com\/.*\/(.*)\/tarball\//) {
		gsub("\/tarball\/.*", "/downloads", url)
		d("github tarball url, mungled url to: " url)
	}


	d("Retrieving: " url)
	cmd = "wget --user-agent \"Mozilla/5.0 (X11; U; Linux x86_64; en-US; rv:1.9.2) Gecko/20100129 PLD/3.0 (Th) Iceweasel/3.6\" -nv -O - \"" url "\" -t 2 -T 45 --passive-ftp --no-check-certificate > " tmpfile " 2> " tmpfileerr
	d("Execute: " cmd)
	errno = system(cmd)
	d("Execute done")

	if (errno==0) {
		wholeodp = ""
		d("Reading succeess response...")
		while (getline oneline < tmpfile)
			wholeodp=(wholeodp " " oneline)
#			d("Response: " wholeodp)
	} else {
		d("Reading failure response...")
		wholeerr = ""
		while (getline oneline < tmpfileerr)
			wholeerr=(wholeerr " " oneline)
		d("Error Response: " wholeerr)
	}

	system("rm -f " tmpfile)
	system("rm -f " tmpfileerr)

	urldir=url;
	sub(/[^\/]+$/,"",urldir)

	if ( errno==0) {
		while (match(wholeodp, /<([aA]|[fF][rR][aA][mM][eE])[ \t][^>]*>/) > 0) {
			d("Processing links...")
			odp=substr(wholeodp,RSTART,RLENGTH);
			wholeodp=substr(wholeodp,RSTART+RLENGTH);

			lowerodp=tolower(odp);
			if (lowerodp ~ /<frame[ \t]/) {
				sub(/[sS][rR][cC]=[ \t]*/,"src=",odp);
				match(odp,/src="[^"]+"/)
				newurl=substr(odp,RSTART+5,RLENGTH-6)
				d("Frame: " newurl)
				if (newurl !~ /\//) {
					newurl=(urldir newurl)
					d("Frame->: " newurl)
				}

				if (link_seen(newurl)) {
					newurl=""
					continue
				}

				retval=(retval " " get_links(newurl))
			} else if (lowerodp ~ /href=[ \t]*"[^"]*"/) {
				sub(/[hH][rR][eE][fF]=[ \t]*"/,"href=\"",odp)
				match(odp,/href="[^"]*"/)
				link=substr(odp,RSTART,RLENGTH)
				odp=substr(odp,1,RSTART) substr(odp,RSTART+RLENGTH)
				link=substr(link,7,length(link)-7)
				link=postfix_link(url, link)

				if (link_seen(link)) {
					link=""
					continue
				}

				retval=(retval " " link)
				d("href(\"\"): " link)
			} else if (lowerodp ~ /href=[ \t]*'[^']*'/) {
				sub(/[hH][rR][eE][fF]=[ \t]*'/,"href='",odp)
				match(odp,/href='[^']*'/)
				link=substr(odp,RSTART,RLENGTH)
				odp=substr(odp,1,RSTART) substr(odp,RSTART+RLENGTH)
				link=substr(link,7,length(link)-7)
				link=postfix_link(url, link)

				if (link_seen(link)) {
					link=""
					continue
				}

				retval=(retval " " link)
				d("href(''): " link)
			} else if (lowerodp ~ /href=[ \t]*[^ \t>]*/) {
				sub(/[hH][rR][eE][fF]=[ \t]*/,"href=",odp)
				match(odp,/href=[^ \t>]*/)
				link=substr(odp,RSTART,RLENGTH)
				odp=substr(odp,1,RSTART) substr(odp,RSTART+RLENGTH)
				link=substr(link,6,length(link)-5)

				if (link_seen(link)) {
					link=""
					continue
				}

				retval=(retval " " link)
				d("href(): " link)
			} else {
				# <a ...> but not href - skip
				d("skipping <a > without href: " odp)
			}
		}
	} else {
		retval=("WGET ERROR: " errno ": " wholeerr)
	}


	d("Returning: " retval)
	return retval
}

function subst_defines(var,defs) {
# substitute all possible RPM macros
	while ((var ~ /%{.*}/) || (var ~ /%[A-Za-z0-9_]+/)) {
		oldvar=var
		for (j in defs) {
			gsub("%{" j "}", defs[j], var)
			gsub("%" j , defs[j], var)
		}
		if (var==oldvar) {
			if (DEBUG) {
				for (i in defs) {
					d(i " == " defs[i])
				}
			}
			return var
		}
	}
	return var
}

function find_mirror(url) {

	while (succ = (getline line < "mirrors")) {
	    if (succ==-1) { return url }
		nf=split(line,fields,"|")
		if (nf>1){
			origin=fields[1]
			mirror=fields[2]
			mname=fields[3]
			prefix=substr(url,1,length(origin))
			if (prefix==origin){
				d("Mirror fount at " mname)
				close("mirrors")
				return mirror substr(url,length(origin)+1)
			}
		}
	}

	return url
}

function process_source(number,lurl,name,version) {
# fetches file list, and compares version numbers
	d("Processing " lurl)

	if ( index(lurl,version)==0 ) {
		d("There is no version number.")
		return 0
	}

	sub("://",":",lurl)
	sub("/",":/",lurl)
	gsub("[^/]*$",":&",lurl)
	split(lurl,url,":")
	acc=url[1]
	host=url[2]
	dir=url[3]
	filename=url[4]

	if (index(dir,version)) {
		# directory name as version maching mode:
		# if /something/version/name-version.tarball then check
		# in /something/ looking for newer directory
		dir=substr(dir,1,index(dir,version)-1)
		sub("[^/]*$","",dir)
		sub("(\.tar\.(bz|bz2|gz|xz)|zip)$","",filename)
	}

	d("Will check a directory: " dir)
	d("and a file: " filename)

	filenameexp=filename
	gsub("\+","\\+",filenameexp)
	sub(version,"[A-Za-z0-9.]+",filenameexp)
	gsub("\.","\\.",filenameexp)
	d("Expression: " filenameexp)
	match(filename,version)
	prever=substr(filename,1,RSTART-1)
	postver=substr(filename,RSTART+RLENGTH)
	d("Before number: " prever)
	d("and after: " postver)
	newurl=find_mirror(acc "://" host dir)
	#print acc "://" host dir
	#newurl=url[1]"://"url[2]url[3]url[4]
	#newurl=acc "://" host dir filename
	d("Looking at " newurl)

	references=0
	finished=0
	oldversion=version
	odp=get_links(newurl,filename)
	if( odp ~ "ERROR: ") {
		print name "(" number ") " odp
	} else {
		d("WebPage downloaded")
		c=split(odp,linki)
		for (nr=1; nr<=c; nr++) {
			addr=linki[nr]

			d("Found link: " addr)

			# github has very different tarball links that clash with this safe check
			if (!(newurl ~/^(http|https):\/\/github.com\/.*\/tarball/)) {
				if (addr ~ "[-_.0-9A-Za-z~]" filenameexp) {
					continue
				}
			}

			if (addr ~ filenameexp) {
				match(addr,filenameexp)
				newfilename=substr(addr,RSTART,RLENGTH)
				d("Hypothetical new: " newfilename)
				newfilename=fixedsub(prever,"",newfilename)
				newfilename=fixedsub(postver,"",newfilename)
				d("Version: " newfilename)
				if (newfilename ~ /\.(asc|sig|pkg|bin|binary|built)$/) continue
				# strip ending (happens when in directiory name as version matching mode)
				sub("(\.tar\.(bz|bz2|gz|xz)|zip)$","",newfilename)
				if (NUMERIC) {
					if ( compare_ver_dec(version, newfilename)==1 ) {
						d("Yes, there is new one")
						version=newfilename
						finished=1
					}
				} else if ( compare_ver(version, newfilename)==1 ) {
					d("Yes, there is new one")
					version=newfilename
					finished=1
				}
			}
		}
		if (finished==0)
			print name "(" number ") seems ok: " oldversion
		else
			print name "(" number ") [OLD] " oldversion " [NEW] " version
	}
}

# upgrade check for pear package using PEAR CLI
function pear_upgrade(name, ver,    pname, pearcmd, nver) {
	pname = name;
	sub(/^php-pear-/, "", pname);

	pearcmd = "pear remote-info " pname " | awk '/^Latest/{print $NF}'"
	d("pearcmd: " pearcmd)
	pearcmd | getline nver
	close(pearcmd)

	if (compare_ver(ver, nver)) {
		print name " [OLD] " ver " [NEW] " nver
	} else {
		print name " seems ok: " ver
	}

	return
}

function vim_upgrade(name, ver,     mver, nver, vimcmd) {
	# %patchset_source -f ftp://ftp.vim.org/pub/editors/vim/patches/7.2/7.2.%03g 1 %{patchlevel}
	mver = substr(ver, 0, 4)
	vimcmd = "wget -q -O - ftp://ftp.vim.org/pub/editors/vim/patches/"mver"/MD5SUMS|grep -vF .gz|tail -n1|awk '{print $2}'"
	d("vimcmd: " vimcmd)
	vimcmd | getline nver
	close(vimcmd)

	if (compare_ver(ver, nver)) {
		print name " [OLD] " ver " [NEW] " nver
	} else {
		print name " seems ok: " ver
	}
}

function process_data(name,ver,rel,src) {
	if (name ~ /^php-pear-/) {
		return pear_upgrade(name, ver);
	}
	if (name == "vim") {
		return vim_upgrade(name, ver);
	}

# this function checks if substitutions were valid, and if true:
# processes each URL and tries to get current file list
	for (i in src) {
		if ( src[i] ~ /%{nil}/ ) {
			gsub(/\%\{nil\}/, "", src[i])
		}
		if ( src[i] !~ /%{.*}/ && src[i] !~ /%[A-Za-z0-9_]/ )  {
			d("Source: " src[i])
			process_source(i,src[i],name,ver)
		} else {
			print FNAME ":" i ": impossible substitution: " src[i]
		}
	}
}

BEGIN {
	# if U want to use DEBUG, run script with "-v DEBUG=1"
	# or uncomment the line below
	# DEBUG = 1

	errno=system("wget --help > /dev/null 2>&1")
	if (errno) {
		print "No wget installed!"
		exit 1
	}
	if (ARGC>=3 && ARGV[2]=="-n") {
		NUMERIC=1
		for (i=3; i<ARGC; i++) ARGV[i-1]=ARGV[i]
		ARGC=ARGC-1
	}
}

FNR==1 {
	if ( ARGIND != 1 ) {
		# clean frameseen for each ARG
		for (i in frameseen) {
			delete frameseen[i]
		}
		frameseen[0] = 1

		process_data(NAME,VER,REL,SRC)
		NAME="" ; VER="" ; REL=""
		for (i in DEFS) delete DEFS[i]
		for (i in SRC) delete SRC[i]
	}
	FNAME=FILENAME
	DEFS["_alt_kernel"]=""
	DEFS["20"]="\\ "
}

/^[Uu][Rr][Ll]:/&&(URL=="") { URL=subst_defines($2,DEFS) ; DEFS["url"]=URL }
/^[Nn]ame:/&&(NAME=="") { NAME=subst_defines($2,DEFS) ; DEFS["name"]=NAME }
/^[Vv]ersion:/&&(VER=="") { VER=subst_defines($2,DEFS) ; DEFS["version"]=VER }
/^[Rr]elease:/&&(REL=="") { REL=subst_defines($2,DEFS) ; DEFS["release"]=REL }
/^[Ss]ource[0-9]*:/ { if (/(ftp|http|https):\/\//) SRC[FNR]=subst_defines($2,DEFS) }
/%define/ { DEFS[$2]=subst_defines($3,DEFS) }

END {
	process_data(NAME,VER,REL,SRC)
}
