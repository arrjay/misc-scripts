#!/bin/bash

# shoot any scdaemons
pkill scdaemon
pkill gpg-agent

# if I have a gpg2, prefer that.
gpgwrap () { gpg "${@}" ; }
type gpg2 && gpgwrap () { gpg2 "${@}" ; }

# create new masterkey and stubby keys

# display name
if [ -z "${GPG_NAME}" ] ; then GPG_NAME="RJ Bergeron" ; fi
# email
if [ -z "${GPG_EMAIL}" ] ; then GPG_EMAIL="gpg@bad.id" ; fi
# expiry
if [ -z "${GPG_EXPIRY}" ] ; then GPG_EXPIRY="5y"; fi
if [ -z "${GPG_SUBKEY_EXPIRY}" ] ; then GPG_SUBKEY_EXPIRY="18m"; fi
# revocation
#REVOKER="Revoker: 1:BA8571970E65816AFFB15FFEBFC06D3971AAB113 sensitive"
REVOKER=""

# subkey lengths
if [ -z "${ENCRYPTION_SUBKEY_COUNT}" ] ; then ENCRYPTION_SUBKEY_COUNT="2" ; fi
if [ -z "${AUTH_SUBKEY_COUNT}" ] ; then AUTH_SUBKEY_COUNT="2" ; fi
if [ -z "${SIGNING_SUBKEY_COUNT}" ] ; then SIGNING_SUBKEY_COUNT="1" ; fi

# if I don't have a master key, make one
gpgwrap --list-keys "${GPG_EMAIL}" || gpgwrap --gen-key --batch << MASTER_PARAMS
%no-ask-passphrase
%no-protection
Key-Type: rsa
Key-Length: 4096
Key-Usage: cert
Name-Real: ${GPG_NAME}
Name-Email: ${GPG_EMAIL}
Expire-Date: ${GPG_EXPIRY}
Preferences: SHA512 SHA384 SHA256 SHA224 AES256 AES192 AES CAST5 ZLIB BZIP2 ZIP Uncompressed
${REVOKER}
MASTER_PARAMS

# create unexpired encryption subkeys
while [ $(gpgwrap --list-keys --with-colons "${GPG_EMAIL}" | grep "sub:u:4096" | grep -c "e::::::") != ${ENCRYPTION_SUBKEY_COUNT} ] ; do
  gpgwrap --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}" << SUBKEY_PARAMS
%no-ask-passphrase
%no-protection
addkey
rsa/e
4096
${GPG_SUBKEY_EXPIRY}
save
SUBKEY_PARAMS
done

# ditto authentication
while [ $(gpgwrap --list-keys --with-colons "${GPG_EMAIL}" | grep "sub:u:4096" | grep -c "a::::::") != ${AUTH_SUBKEY_COUNT} ] ; do
  gpgwrap --expert --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}" << SUBKEY_PARAMS
%no-ask-passphrase
%no-protection
addkey
rsa/*
=a
4096
${GPG_SUBKEY_EXPIRY}
save
SUBKEY_PARAMS
done

# and signing
while [ $(gpgwrap --list-keys --with-colons "${GPG_EMAIL}" | grep "sub:u:4096" | grep -c "s::::::") != ${SIGNING_SUBKEY_COUNT} ] ; do
  gpgwrap --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}" << SUBKEY_PARAMS
%no-ask-passphrase
%no-protection
addkey
rsa/s
4096
${GPG_SUBKEY_EXPIRY}
save
SUBKEY_PARAMS
done

# so, the theory here is we'll order subkeys and load by expiry - the first export contains the last to expire
# and types s/e/a. the second blob contains the next e/a keys. the c key doesn't get exported until we backup the
# whole thing.

# track loaded keys here
loaded=""
_one=""
_two=""
one=""
two=""

for l in e s a ; do
_one="${_one} $(gpgwrap --list-keys --with-colons "${GPG_EMAIL}" | grep "sub:u:4096" | grep "${l}::::::" |awk -F: '{ key[$7]=$5 } END { asort(key) ; print key[1] }')"
_two="${_two} $(gpgwrap --list-keys --with-colons "${GPG_EMAIL}" | grep "sub:u:4096" | grep "${l}::::::" |awk -F: '{ key[$7]=$5 } END { asort(key) ; print key[2] }')"
done

for k in ${_one} ; do
  one="${one} 0x${k}!"
done
for k in ${_two} ; do
  two="${two} ${k}!"
done

loaded="${one} ${two}"

# export the private keys to files
gpgwrap --export-secret-subkeys -a ${one} > ${GPG_EMAIL}-redone.asc
gpgwrap --export-secret-subkeys -a ${two} > ${GPG_EMAIL}-redtwo.asc

rm -rf scratch
mkdir scratch
echo 'reader-port "Yubico Yubikey NEO OTP+U2F+CCID 01 00"' > scratch/scdaemon.conf
GNUPGHOME=$(pwd)/scratch gpgwrap --import "${GPG_EMAIL}-redone.asc"
GNUPGHOME=$(pwd)/scratch gpgwrap --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}" << TRUST
trust
5
y
save
TRUST

# we need to actually get the order the subkeys were written in for card writing
ekey=$(GNUPGHOME=$(pwd)/scratch gpgwrap --list-keys --with-colons 2>/dev/null | grep 'sub:u:' | grep -n ':e::::::')
ekey=${ekey:0:1}
akey=$(GNUPGHOME=$(pwd)/scratch gpgwrap --list-keys --with-colons 2>/dev/null | grep 'sub:u:' | grep -n ':a::::::')
akey=${akey:0:1}
skey=$(GNUPGHOME=$(pwd)/scratch gpgwrap --list-keys --with-colons 2>/dev/null | grep 'sub:u:' | grep -n ':s::::::')
skey=${skey:0:1}

# now that we know which key is which, push to card. you will be prompted for the admin pin.
printf '\nrun:\ntoggle\nkey %s\nkeytocard\n1\nsave\n\n' ${skey}
GNUPGHOME=$(pwd)/scratch gpgwrap --edit-key "${GPG_EMAIL}"
#toggle
#key ${skey}
#keytocard
#1
#save
#S2CARD

printf '\nrun:\ntoggle\nkey %s\nkeytocard\n2\nsave\n\n' ${ekey}
GNUPGHOME=$(pwd)/scratch gpgwrap --edit-key "${GPG_EMAIL}"

printf '\nrun:\ntoggle\nkey %s\nkeytocard\n3\nsave\n\n' ${akey}
GNUPGHOME=$(pwd)/scratch gpgwrap --edit-key "${GPG_EMAIL}"

# export the resulting stubby key
GNUPGHOME=$(pwd)/scratch gpgwrap --export-secret-subkeys "${GPG_EMAIL}" > ${GPG_EMAIL}-blackone.gpg

ekey=""
akey=""

pkill scdaemon
pkill gpg-agent
rm -rf scratch
mkdir scratch
echo 'reader-port "Yubico Yubikey NEO OTP+U2F+CCID 01 00"' > scratch/scdaemon.conf
GNUPGHOME=$(pwd)/scratch gpgwrap --import "${GPG_EMAIL}-redtwo.asc"
GNUPGHOME=$(pwd)/scratch gpgwrap --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}" << TRUST
trust
5
y
save
TRUST

ekey=$(GNUPGHOME=$(pwd)/scratch gpgwrap --list-keys --with-colons 2>/dev/null | grep 'sub:u:' | grep -n ':e::::::')
ekey=${ekey:0:1}
akey=$(GNUPGHOME=$(pwd)/scratch gpgwrap --list-keys --with-colons 2>/dev/null | grep 'sub:u:' | grep -n ':a::::::')
akey=${akey:0:1}

printf '\nrun:\ntoggle\nkey %s\nkeytocard\n2\nsave\n\n' ${ekey}
GNUPGHOME=$(pwd)/scratch gpgwrap --edit-key "${GPG_EMAIL}"

printf '\nrun:\ntoggle\nkey %s\nkeytocard\n3\nsave\n\n' ${akey}
GNUPGHOME=$(pwd)/scratch gpgwrap --edit-key "${GPG_EMAIL}"

# export the resulting stubby key
GNUPGHOME=$(pwd)/scratch gpgwrap --export-secret-subkeys "${GPG_EMAIL}" > ${GPG_EMAIL}-blacktwo.gpg

pkill scdaemon
pkill gpg-agent
rm -rf scratch

# shred the previous exports
shred ${GPG_EMAIL}-redone.asc
shred ${GPG_EMAIL}-redtwo.asc

# import the second key and grab everything in it
mkdir scratch
GNUPGHOME=$(pwd)/scratch gpgwrap --import "${GPG_EMAIL}-blacktwo.gpg"
GNUPGHOME=$(pwd)/scratch gpgwrap --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}" << TRUST
trust
5
y
save
TRUST

pubkeys="0x$(GNUPGHOME=$(pwd)/scratch gpgwrap --list-keys --with-colons 2>/dev/null | grep 'sub:u:' | grep ':e::::::' | cut -d: -f5)!"

# now import the first key
GNUPGHOME=$(pwd)/scratch gpgwrap --import "${GPG_EMAIL}-blackone.gpg"

# and grab all the other keys
for l in $(GNUPGHOME=$(pwd)/scratch gpgwrap --list-keys --with-colons|grep 'sub:u:'|cut -d: -f5,12 | grep -E '(a|s)$') ; do
  pubkeys="${pubkeys} 0x${l%:*}!"
done

GNUPGHOME=$(pwd)/scratch gpgwrap --export -a ${pubkeys} > ${GPG_EMAIL}-upload.asc

# now assemble a legacy gpg keyring...
mkdir one
mkdir two
( cd one && gpgsplit ../"${GPG_EMAIL}-blackone.gpg" )
( cd two && gpgsplit ../"${GPG_EMAIL}-blacktwo.gpg" )
fdupes -dN one two
cat one/* two/* > "${GPG_EMAIL}-gpg14.gpg"
