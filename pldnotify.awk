#!/bin/awk -f

function subst_defines(var,defs) {
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

function process_source(lurl,version) {
	sub("://",":",lurl)
	sub("/",":/",lurl)
	gsub("[^/]*$",":&",lurl)
	split(lurl,url,":")
	acc=url[1]
	host=url[2]
	dir=url[3]
	if ( DEBUG ) print acc "://" host dir 
	
	references=0
	while ( "lynx --dump " acc "://" host dir | getline result ) {
		if ( result ~ "References" ) references=1
		if ( result ~ "[0-9]+\. (ftp|http)://" ) {
			split(result,links)
			addr=links[2]
			# if (DEBUG)
			print addr
		}
	}
}
	
function process_data(name,ver,rel,defs,src) {
	for (i in src) {
		if ( src[i] !~ /%{.*}/ && src[i] !~ /%[A-Za-z0-9_]/ )  {
			if ( DEBUG ) print "Zrodlo: " src[i]
			# process_source(src[i],defs["version"])
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
		process_data(NAME,VER,REL,DEFS,SRC)
		NAME="" ; VER="" ; REL=""
		for (i in DEFS) delete DEFS[i]
		for (i in SRC) delete SRC[i]
	}
	FNAME=FILENAME
}

/^[Nn]ame:/&&(NAME=="") { NAME=subst_defines($2,DEFS) ; DEFS["name"]=NAME }
/^[Vv]ersion:/&&(VER=="") { VER=subst_defines($2,DEFS) ; DEFS["version"]=VER }
/^[Rr]elease:/&&(REL=="") { REL=subst_defines($2,DEFS) ; DEFS["release"]=REL }
/^[Ss]ource[0-9]*:/ { if (/(ftp|http):\/\//) SRC[FNR]=subst_defines($2,DEFS) }
/%define/ { DEFS[$2]=subst_defines($3,DEFS) }

END {
	process_data(NAME,VER,REL,DEFS,SRC)
}
