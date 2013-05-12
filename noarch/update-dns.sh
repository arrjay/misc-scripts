#!/bin/bash

# load config (DELEGATION, NS, KEYFILE, DOMAIN)
. /usr/local/etc/update-dns.conf

# call with (add|delete) IP [NAME]
action=$1
ip=$2
name=$(echo $3 | awk -F '.' '{ print $1 }')

loctet=$(echo $ip | awk -F '.' '{ print $4 }')

# attempt to look up name if expiring a deletion
if [ -n "${name}" ]; then
	name=$(dig -t PTR ${loctet}.${DELEGATION} @${NS} | grep 'IN PTR' | awk '{ print $5 }' | awk -F '.' '{ print $1 }')
fi

# err, if we still don't have a name, make something up
if [ -n "${name}" ]; then
	name="dynclient-${loctet}"
fi

# see if we are reissuing an IP
oldname=$(dig -t PTR ${loctet}.${DELEGATION} @${NS} | grep 'IN PTR' | awk '{ print $5 }' | awk -F '.' '{ print $1 }')

case "$action" in
	add)
		UPDATE=$(mktemp)
		printf "server %s\n" ${NS} > ${UPDATE}
		printf "zone %s\n" ${DOMAIN} >> ${UPDATE}
		if [ -n "${oldname}" ]; then
			printf "update delete %s 3600 A\n" ${oldname}.${DOMAIN} >> ${UPDATE}
		fi
		printf "update delete %s 3600 A\n" ${name}.${DOMAIN} >> ${UPDATE}
		printf "update add %s 3600 A %s\n" ${name}.${DOMAIN} ${ip} >> ${UPDATE}
		printf "send\n" >> ${UPDATE}
		nsupdate -k "${KEYFILE}" "${UPDATE}"
		rm "$UPDATE"

		UPDATE=$(mktemp)
		printf "server %s\n" ${NS} > ${UPDATE}
		printf "zone %s\n" ${DELEGATION} >> ${UPDATE}
		printf "update delete %s 3600 PTR\n" ${loctet}.${DELEGATION} >> ${UPDATE}
		printf "update add %s 3600 PTR %s\n" ${loctet}.${DELEGATION} ${name}.${DOMAIN} >> ${UPDATE}
		printf "send\n" >> ${UPDATE}
		nsupdate -k "${KEYFILE}" "${UPDATE}"
		rm "${UPDATE}"
		;;
	delete)
		if [ -n "${name}" ]; then
			UPDATE=$(mktemp)
			printf "server %s\n" ${NS} > ${UPDATE}
			printf "zone %s\n" ${DOMAIN} >> ${UPDATE}
			printf "update delete %s 3600 A\n" ${name}.${DOMAIN} >> ${UPDATE}
			printf "send\n" >> ${UPDATE}
			nsupdate -k "${KEYFILE}" "${UPDATE}"
			rm "$UPDATE"
		fi
		UPDATE=$(mktemp)
		printf "server %s\n" ${NS} > ${UPDATE}
		printf "zone %s\n" ${DELEGATION} >> ${UPDATE}
		printf "update delete %s 3600 PTR\n" ${loctet}.${DELEGATION} >> ${UPDATE}
		printf "send\n" >> ${UPDATE}
		nsupdate -k "${KEYFILE}" "${UPDATE}"
		rm "${UPDATE}"
		;;
	*)
		# noop!
		;;
esac
