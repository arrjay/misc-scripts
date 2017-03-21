#!/bin/bash

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
gpg2 --list-keys "${GPG_EMAIL}"
if [ "${?}" -ne 0 ] ; then
  gpg2 --gen-key --batch << MASTER_PARAMS
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
fi

# create unexpired encryption subkeys
while [ $(gpg2 --list-keys --with-colons "${GPG_EMAIL}" | grep "sub:u:4096" | grep -c "e::::::") != ${ENCRYPTION_SUBKEY_COUNT} ] ; do
  gpg2 --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}" << SUBKEY_PARAMS
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
while [ $(gpg2 --list-keys --with-colons "${GPG_EMAIL}" | grep "sub:u:4096" | grep -c "a::::::") != ${AUTH_SUBKEY_COUNT} ] ; do
  gpg2 --expert --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}" << SUBKEY_PARAMS
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
while [ $(gpg2 --list-keys --with-colons "${GPG_EMAIL}" | grep "sub:u:4096" | grep -c "s::::::") != ${SIGNING_SUBKEY_COUNT} ] ; do
  gpg2 --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}" << SUBKEY_PARAMS
%no-ask-passphrase
%no-protection
addkey
rsa/s
4096
${GPG_SUBKEY_EXPIRY}
save
SUBKEY_PARAMS
done

# this holds all the things for the final minified export
subs=""

# export signing pubkey for sign checkers
signs=$(gpg2 --list-keys --with-colons "${GPG_EMAIL}" | grep "sub:u:" | grep "s::::::" | cut -d: -f5)
for s in ${signs} ; do
  subs="${s}! ${subs}"
  gpg2 --export --armor --export-options export-minimal --no-emit-version "${s}!" > "${GPG_EMAIL}-signing-${s}.asc"
done

# export auth pubkeys as ssh pubkeys
auths=$(gpg2 --list-keys --with-colons "${GPG_EMAIL}" | grep "sub:u:" | grep "a::::::" | cut -d: -f5)
for a in ${auths} ; do
  subs="${a}! ${subs}"
  gpg2 --export --armor --export-options export-minimal --no-emit-version "${a}!" > "${GPG_EMAIL}-auth-${a}.asc"
  gpg2 --export --export-options export-minimal --no-emit-version "${a}!" | openpgp2ssh "${a}" > "${GPG_EMAIL}-auth-${a}.pub"
done

# export largest crypt key for decrypters
crypts=$(gpg2 --list-keys --with-colons "${GPG_EMAIL}" | grep "sub:u:" | grep "e::::::" | sort | tail -n1 | cut -d: -f5)
for c in ${crypts} ; do
  subs="${c}! ${subs}"
  gpg2 --export --armor --export-options export-minimal --no-emit-version "${c}!" > "${GPG_EMAIL}-crypt-${c}.asc"
done

# make a combo key for that
mkdir scratch
env GNUPGHOME=scratch gpg2 --import "${GPG_EMAIL}"-*.asc
env GNUPGHOME=scratch gpg2 --export -a "${GPG_EMAIL}" > "${GPG_EMAIL}-minified.asc"
rm -rf scratch

# dump all da pubkeys
gpg2 --export -a "${GPG_EMAIL}" > "${GPG_EMAIL}-full.asc"
