#!/bin/awk -f
# $Revision$, $Date$

function compare_ver(v1,v2) {
# compares version numbers
	while (match(v1,/[a-zA-Z][0-9]|[0-9][a-zA-Z]/))
		v1=(substr(v1,1,RSTART) "." substr(v1,RSTART+RLENGTH-1))
	while (match(v2,/[a-zA-Z][0-9]|[0-9][a-zA-Z]/))
		v2=(substr(v2,1,RSTART) "." substr(v2,RSTART+RLENGTH-1))
	sub("^0*","",v1)
	sub("^0*","",v2)
	if (DEBUG) print "v1 == " v1
	if (DEBUG) print "v2 == " v2
	count=split(v1,v1a,"\.")
	count2=split(v2,v2a,"\.")
	
	if (count<count2) mincount=count 
	else mincount=count2
	
	for (i=1; i<=mincount; i++) {
		if (v1a[i]=="") v1a[i]=0
		if (v2a[i]=="") v2a[i]=0
		if (DEBUG) print "i == " i
		if (DEBUG) print "v1[i] == " v1a[i]
		if (DEBUG) print "v2[i] == " v2a[i]
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
		} else if ((v1a[i]~"pre")||(v1a[i]~"beta")||(v1a[i]~"^b$"))
			return 1
		else
			return 0
	}
	if ((count2==mincount)&&(count!=count2)) {
		for (i=count2+1; i<=count; i++)
			if ((v1a[i]~"pre")||(v1a[i]~"beta")||(v1a[i]~"^b$")) 
				return 1
		return 0
	} else if (count!=count2) {
		for (i=count+1; i<=count2; i++)
			if ((v2a[i]~"pre")||(v2a[i]~"beta")||(v2a[i]~"^b$"))
				return 0
		return 1
	}
	return 0
}

function get_http_links(host,dir,port,	errno,link,oneline,retval,odp,tmpfile) {
# get all <A HREF=..> tags from specified URL
	"mktemp /tmp/XXXXXX" | getline tmpfile
	close("mktemp /tmp/XXXXXX")
	errno=system("echo -e \"GET " dir "\\n\" | nc " host " " port " | tr -d '\\r' > " tmpfile )
	
	if (errno==0) {
		getline oneline < tmpfile
		if ( oneline ~ "200" ) {
			while (getline oneline < tmpfile)
				odp=(odp " " oneline)
			if ( DEBUG ) print "Odpowiedz: " odp
		} else {
			match(oneline,"[0-9][0-9][0-9]")
			errno=substr(oneline,RSTART,RLENGTH)
		}
	}
		
	close(tmpfile)
		
	if ( errno==0) {
		while (tolower(odp) ~ /href=/) {
			match(tolower(odp),/href="[^"]+"/)
			link=substr(odp,RSTART,RLENGTH)
			odp=substr(odp,RSTART+RLENGTH)
			link=substr(link,7,length(link)-7)
			retval=(retval " " link)
		}
	} else {
		retval=("HTTP ERROR: " errno)
	}
	
	system("rm -f " tmpfile)
	
	if (DEBUG) print "Zwracane: " retval
	return retval
}

function get_ftp_links(host,dir,port,	tmpfile,link,retval) {
	"mktemp /tmp/XXXXXX" | getline tmpfile
	close("mktemp /tmp/XXXXXX")
	
	errno=system("export PLIKTMP=\"" tmpfile "\" FTP_DIR=\"" dir "\" FTP_PASS=\"pldnotifier@pld.org.pl\" FTP_USERNAME=\"anonymous\" FTP_HOST=\"" host "\" DEBUG=\"" DEBUG "\" ; nc -e \"./ftplinks.sh\" " host " " port)
	
	if (errno==0) {
		while (getline link < tmpfile)
			retval=(retval " " link)
		close(tmpfile)
	} else {
		retval=("FTP ERROR: " errno)
	}

	system("rm -f " tmpfile)
	
	if (DEBUG) print "Zwracane: " retval
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
			if ( DEBUG ) for (i in defs) print i " == " defs[i]
			return var
		}
	}
	return var
}

function process_source(number,lurl,name,version) {
# fetches file list, and compares version numbers
	if ( DEBUG ) print "Przetwarzam " lurl

	if ( index(lurl,version)==0 ) {
		if (DEBUG) print "Nie ma numeru wersji."
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
		dir=substr(dir,1,index(dir,version)-1)
		sub("[^/]*$","",dir)
		sub("(\.tar\.(bz|bz2|gz)|zip)$","",filename)
		if ( DEBUG ) print "Sprawdze katalog: " dir
		if ( DEBUG ) print "i plik: " filename
	}

	filenameexp=filename
	gsub("\+","\\+",filenameexp)
	sub(version,"[A-Za-z0-9\\.]+",filenameexp)
	if ( DEBUG ) print "Wzorzec: " filenameexp
	match(filename,version)
	prever=substr(filename,1,RSTART-1)
	postver=substr(filename,RSTART+RLENGTH)
	if ( DEBUG ) print "Przed numerkiem: " prever
	if ( DEBUG ) print "i po: " postver
	
	if ( DEBUG ) print "Zagl±dam na " acc "://" host dir 
	
	references=0
	finished=0
	oldversion=version
	if (acc=="http") 
		odp=get_http_links(host,dir,80)
	else {
		odp=get_ftp_links(host,dir,21)
	}
	if( odp ~ "ERROR: ") {
		print name "(" number ") " odp
	} else {
		c=split(odp,linki)
		for (nr=1; nr<=c; nr++) {
			addr=linki[nr]
			if (DEBUG) print "Znaleziony link: " addr
			if (addr ~ filenameexp) {
				match(addr,filenameexp)
				newfilename=substr(addr,RSTART,RLENGTH)
				if (DEBUG) print "Hipotetyczny nowy: " newfilename
				sub(prever,"",newfilename)
				sub(postver,"",newfilename)
				if (DEBUG) print "Wersja: " newfilename
				if ( compare_ver(version, newfilename)==1 ) {
					if (DEBUG) print "Tak, jest nowa"
					version=newfilename
					finished=1
				}
			}
		}
		if (finished==0)
			print name "(" number ") seems ok"
		else
			print name "(" number ") [OLD] " oldversion " [NEW] " version
	}
}
	
function process_data(name,ver,rel,src) {
# this function checks if substitutions were valid, and if true:
# processes each URL and tries to get current file list
	for (i in src) {
		if ( src[i] !~ /%{.*}/ && src[i] !~ /%[A-Za-z0-9_]/ )  {
			if ( DEBUG ) print "Zrodlo: " src[i]
			process_source(i,src[i],name,ver)
		} else {
			print FNAME ":" i ": niemozliwe podstawienie: " src[i]
		}
	}
}

BEGIN {
	# if U want to use DEBUG, run script with "-v DEBUG=1"
	# or uncomment the line below
	# DEBUG = 1
}

FNR==1 {
	if ( ARGIND != 1 ) {
		process_data(NAME,VER,REL,SRC)
		NAME="" ; VER="" ; REL=""
		for (i in DEFS) delete DEFS[i]
		for (i in SRC) delete SRC[i]
	}
	FNAME=FILENAME
}

/^[Uu][Rr][Ll]:/&&(URL=="") { URL=subst_defines($2,DEFS) ; DEFS["url"]=URL }
/^[Nn]ame:/&&(NAME=="") { NAME=subst_defines($2,DEFS) ; DEFS["name"]=NAME }
/^[Vv]ersion:/&&(VER=="") { VER=subst_defines($2,DEFS) ; DEFS["version"]=VER }
/^[Rr]elease:/&&(REL=="") { REL=subst_defines($2,DEFS) ; DEFS["release"]=REL }
/^[Ss]ource[0-9]*:/ { if (/(ftp|http):\/\//) SRC[FNR]=subst_defines($2,DEFS) }
/%define/ { DEFS[$2]=subst_defines($3,DEFS) }

END {
	process_data(NAME,VER,REL,SRC)
}
