#!/bin/bash
basedir=".."
outputdir="output/bind"
zonefile="output/bind/cache.zone.template"
path="${basedir}/cache_domains.json"

export IFS=' '

test=$(which jq);
out=$?
if [ $out -gt 0 ] ; then
	echo "This script requires jq to be installed."
	echo "Your package manager should be able to find it"
	exit 1
fi

cachenamedefault="disabled"

if [ -s config.json ]; then
	echo "Found config.json, creating DNS zonefiles from config"
	while read line; do 
		ip=$(jq -r ".ips[\"${line}\"]" config.json)
		declare "cacheip$line"="$ip"
	done <<< $(jq -r '.ips | to_entries[] | .key' config.json)

	while read line; do 
		name=$(jq -r ".cache_domains[\"${line}\"]" config.json)
		declare "cachename$line"="$name"
	done <<< $(jq -r '.cache_domains | to_entries[] | .key' config.json)
else
	echo "No config found, creating DNS templates for all entries"
	STEAMCACHEDNS=true
fi

rm -rf ${outputdir}
mkdir -p ${outputdir}
while read entry; do 
	unset cacheip
	unset cachename
	key=$(jq -r ".cache_domains[$entry].name" $path)
	cachename="cachename${key}"
	if [ -z "${!cachename}" ]; then
		cachename="cachenamedefault"
	fi
	if ! [ "$STEAMCACHEDNS" ]; then
		if [[ ${!cachename} == "disabled" ]]; then
			continue;
		fi
	fi
	cacheipname="cacheip${!cachename}"
	cacheip=${!cacheipname}
	touch $zonefile
	while read fileid; do
		while read filename; do
			if [ "$STEAMCACHEDNS" ]; then
				destfilename="$(echo $filename | sed -e 's/txt/conf.template/')"
				DNS_IP="{{ ${key}_ip }}"
			else
				destfilename="$(echo $filename | sed -e 's/txt/conf/')"
				DNS_IP="$cacheip"
			fi
			mkdir -p ${outputdir}/cache/${key}
			outputfile=${outputdir}/cache/${key}/${destfilename}
			touch $outputfile
			cat > $outputfile <<!EOF
\$TTL	600
@		IN	SOA	ns1 dns.steamcache.net. (
		$(date +%Y%m%d%M)
		604800
		600
		600
		600 )
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                                                                      ;;
;;    This config is automatically generated from uklans/cache-domains  ;;
;;                                                                      ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

@		IN	NS	ns1
ns1		IN	A	${DNS_IP}

@		IN	A	${DNS_IP}
*		IN	A	${DNS_IP}
!EOF
			while read fileentry; do
				
				# Ignore comments
				if [[ $fileentry == \#* ]]; then
					continue
				fi
				# For bind we're going to keep it simple and create a ZONE file for each domain/subdomain.
				parsed=$(echo $fileentry | sed -e "s/^\*\.//")
				if grep -q "$parsed" $zonefile; then
					continue
				fi
				echo "zone \"$( echo ${fileentry} | sed -e "s/^\*\.//")\"  {type master; file \"/etc/bind/cache/${key}.conf\";};" >> $zonefile
			done <<< $(cat ${basedir}/$filename);
		done <<< $(jq -r ".cache_domains[$entry].domain_files[$fileid]" $path)
	done <<< $(jq -r ".cache_domains[$entry].domain_files | to_entries[] | .key" $path)
done <<< $(jq -r '.cache_domains | to_entries[] | .key' $path)
