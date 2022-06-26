#!/bin/bash

# shoot any scdaemons
pkill scdaemon
pkill gpg-agent

# if I have a gpg2, prefer that.
gpgwrap () { command gpg "${@}" ; }
type gpg2 > /dev/null 2>&1 && gpgwrap () { command gpg2 "${@}" ; }

# set up a script-temp directory to clean up later
sc_temp="$(mktemp -d)"
export TMPDIR="${sc_temp}"

_atexit () {
  last="${?}"
  [[ "${last}" -eq 0 ]] && {
    case "${sc_temp}" in
      /|/tmp) : ;;
      *) rm -rf "${sc_temp}" ;;
    esac
  }
  return "${last}"
}

trap _atexit EXIT

# display name
GPG_NAME="RJ Bergeron"
# email
GPG_EMAIL="gpg@bad.id"
# expiry
GPG_EXPIRY="5y"
GPG_SUBKEY_EXPIRY="18m"
# revocation
#REVOKER="Revoker: 1:BA8571970E65816AFFB15FFEBFC06D3971AAB113 sensitive"
REVOKER=""

# option processing
_ext_opts=""

selfhelp () {
  {
    printf '%s\n' "attempt to create a gpg key set for practical use."
  } >&2
  exit 0
}

while getopts "e:n:x:s:r:fh" _opt ; do
  case "${_opt}" in
    e) GPG_EMAIL="${OPTARG}" ;;
    n) GPG_NAME="${OPTARG}" ;;
    x) GPG_EXPIRY="${OPTARG}" ;;
    s) GPG_SUBKEY_EXPIRY="${OPTARG}" ;;
    r) REVOKER="${OPTARG}" ;;
    *) selfhelp ;;
  esac
done

# create new working directory for gpg
gpgscratch="$(mktemp -d)"
my_gpg () { GNUPGHOME="${gpgscratch}" gpgwrap "${@}" ; }
# write a scratch config for that gpg as well.
cat <<GPGCONF >"${gpgscratch}/gpg.conf"
# from https://ngkz.github.io/2020/01/gpg-hardening/
cert-digest-algo SHA512
personal-cipher-preferences AES256 AES192 AES CAST5
personal-digest-preferences SHA512 SHA384 SHA256 SHA224
default-preference-list SHA512 SHA384 SHA256 SHA224 AES256 AES192 AES CAST5 ZLIB BZIP2 ZIP Uncompressed
weak-digest SHA1
disable-cipher-algo 3DES
s2k-cipher-algo AES256
s2k-digest-algo SHA512
s2k-count 65011712
keyid-format none
with-subkey-fingerprint
GPGCONF

# check existing gpg chain for a master key with secret
case $(gpgwrap --list-secret-keys --with-colons --with-fingerprint --with-fingerprint "${GPG_EMAIL}" | \
 awk -F: 'BEGIN { c=0 } END { print c } ($1 == "sec" && $2 == "u" && $9 == "u" && $15 == "+") { c++ }') in
 0) # create a key on the scratch keychain
 # if I don't have a master key, make one
  {
    printf '%s\n' \
     "%no-ask-passphrase" \
     "%no-protection" \
     "Key-Type: rsa" \
     "Key-Length: 4096" \
     "Key-Usage: cert"
    printf 'Name-Real: %s\n' "${GPG_NAME}"
    printf 'Name-Email: %s\n' "${GPG_EMAIL}"
    printf 'Expire-Date: %s\n' "${GPG_EXPIRY}"
    printf 'Preferences: %s\n' \
     "SHA512 SHA384 SHA256 SHA224 AES256 AES192 AES CAST5 ZLIB BZIP2 ZIP Uncompressed"
    [[ -n "${REVOKER}" ]] && printf 'Revoker: %s sensitive\n' "${REVOKER}"
  } | my_gpg --gen-key --batch
 ;;
 1) # copy the master key to a scratch keychain
  gpgwrap --export-secret-keys "${GPG_EMAIL}" | my_gpg --import
 ;;
 *) # panic
  exit 1
 ;;
esac

# create unexpired encryption subkeys for card
my_gpg --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}" << SUBKEY_PARAMS
%no-ask-passphrase
%no-protection
addkey
rsa/e
4096
${GPG_SUBKEY_EXPIRY}
save
SUBKEY_PARAMS

# ditto authentication
my_gpg --expert --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}" << SUBKEY_PARAMS
%no-ask-passphrase
%no-protection
addkey
rsa/*
=a
4096
${GPG_SUBKEY_EXPIRY}
save
SUBKEY_PARAMS

# and signing
my_gpg --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}" << SUBKEY_PARAMS
%no-ask-passphrase
%no-protection
addkey
rsa/s
4096
${GPG_SUBKEY_EXPIRY}
save
SUBKEY_PARAMS

# so, the theory here is we'll order subkeys and load by expiry - the first export contains the last to expire
# and types s/e/a. the second blob contains the next e/a keys. the c key doesn't get exported until we backup the
# whole thing.

# track loaded keys here
loaded=""
_one=""
one=""

for l in e s a ; do
_one="${_one} $(my_gpg --list-keys --with-colons "${GPG_EMAIL}" | grep "sub:u:4096" | grep "${l}::::::" |gawk -F: '{ key[$7]=$5 } END { asort(key) ; print key[1] }')"
done

for k in ${_one} ; do
  one="${one} 0x${k}!"
done

loaded="${one}"

# export the private keys to files
my_gpg --export-secret-subkeys -a "${one}" > "${GPG_EMAIL}-redone.asc"

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
printf '\nrun:\ntoggle\nkey %s\nkeytocard\n1\nsave\n\n' "${skey}"
GNUPGHOME=$(pwd)/scratch gpgwrap --edit-key "${GPG_EMAIL}"
#toggle
#key ${skey}
#keytocard
#1
#save
#S2CARD

printf '\nrun:\ntoggle\nkey %s\nkeytocard\n2\nsave\n\n' "${ekey}"
GNUPGHOME=$(pwd)/scratch gpgwrap --edit-key "${GPG_EMAIL}"

printf '\nrun:\ntoggle\nkey %s\nkeytocard\n3\nsave\n\n' "${akey}"
GNUPGHOME=$(pwd)/scratch gpgwrap --edit-key "${GPG_EMAIL}"

# export the resulting stubby key
GNUPGHOME=$(pwd)/scratch gpgwrap --export-secret-subkeys "${GPG_EMAIL}" > "${GPG_EMAIL}-blackone.gpg"

ekey=""
akey=""

pkill scdaemon
pkill gpg-agent

pkill scdaemon
pkill gpg-agent
rm -rf scratch

# shred the previous exports
shred "${GPG_EMAIL}-redone.asc"

# and grab all the other keys
for l in $(GNUPGHOME=$(pwd)/scratch gpgwrap --list-keys --with-colons|grep 'sub:u:'|cut -d: -f5,12 | grep -E '(a|s)$') ; do
  pubkeys="${pubkeys} 0x${l%:*}!"
done

GNUPGHOME=$(pwd)/scratch gpgwrap --export -a "${pubkeys}" > "${GPG_EMAIL}-upload.asc"

# now assemble a legacy gpg keyring...
mkdir one
( cd one && gpgsplit ../"${GPG_EMAIL}-blackone.gpg" )
fdupes -dN one
cat one/* > "${GPG_EMAIL}-gpg14.gpg"
