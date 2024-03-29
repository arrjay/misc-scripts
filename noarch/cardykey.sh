#!/bin/bash

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
      *)
        find "${sc_temp}" -type f -exec shred {} \;
        rm -rf "${sc_temp}"
      ;;
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
PASS_ITEM=""
LEGACY_SUBKEYING="false"
SIGN_AS_AUTH2="false"

# option processing
_ext_opts=""

selfhelp () {
  {
    printf '%s\n' "attempt to create a gpg key set for practical use."
  } >&2
  exit 0
}

while getopts "e:n:x:s:r:p:Lfh2" _opt ; do
  case "${_opt}" in
    e) GPG_EMAIL="${OPTARG}" ;;
    n) GPG_NAME="${OPTARG}" ;;
    x) GPG_EXPIRY="${OPTARG}" ;;
    s) GPG_SUBKEY_EXPIRY="${OPTARG}" ;;
    r) REVOKER="${OPTARG}" ;;
    p) PASS_ITEM="${OPTARG}" ;;
    L) LEGACY_SUBKEYING="true" ;;
    2) SIGN_AS_AUTH2="true" ;;
    *) selfhelp ;;
  esac
done

# track if we made a key or not (if we made a key, we should export the certifying element)
_made_master=0

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

# check existing gpg chain for a revocation key if configured and grab the needed magic bits
[[ -n "${REVOKER}" ]] && {
  revgrip=$(gpgwrap --list-keys --with-colons --with-fingerprint "${REVOKER}" |\
    awk -F: 'BEGIN { c=0 ; fx=0 ; } END { if (c==1) { print alg,fpr } } ($1 == "pub") { alg=$4 ; fx=1 ; c++ } ($1 == "fpr" && fx == 1) { fx=0 ; fpr=$10 ; }')
  case "${revgrip}" in
  *" "*)
    gpgwrap --export "${REVOKER}" | my_gpg --import
    printf '%s\n' "trust" "5" "y" "save" | \
      my_gpg --edit-key --batch --command-fd 0 --passphrase '' "${REVOKER}"
    REVOKER="${revgrip/ /:}"
  ;;
  *)
    echo "couldn't sort out public key for ${REVOKER} - either missing or duplicates in main keyring" 1>&2
    exit 1
  ;;
  esac
}

# check existing gpg chain for a master key with secret
case $(gpgwrap --list-secret-keys --with-colons --with-fingerprint --with-fingerprint "${GPG_EMAIL}" | \
 awk -F: 'BEGIN { c=0 } END { print c } ($1 == "sec" && $2 == "u" && $9 == "u" && $15 == "+") { c++ }') in
 0) # create a key on the scratch keychain
 # if I don't have a master key, make one
  {
    printf '%s\n' \
     "%no-ask-passphrase" \
     "%no-protection" \
     "Key-Type: eddsa" \
     "Key-Curve: Ed25519" \
     "Key-Usage: sign"
    printf 'Name-Real: %s\n' "${GPG_NAME}"
    printf 'Name-Email: %s\n' "${GPG_EMAIL}"
    printf 'Expire-Date: %s\n' "${GPG_EXPIRY}"
    printf 'Preferences: %s\n' \
     "SHA512 SHA384 SHA256 SHA224 AES256 AES192 AES CAST5 ZLIB BZIP2 ZIP Uncompressed"
    [[ -n "${REVOKER}" ]] && printf 'Revoker: %s\n' "${REVOKER}"
  } | my_gpg --gen-key --batch
  _made_master=1
 ;;
 1) # copy the master key to a scratch keychain
  gpgwrap --export-secret-keys "${GPG_EMAIL}" | my_gpg --import
  printf '%s\n' "trust" "5" "y" "save" | \
   my_gpg --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}"
 ;;
 *) # panic
  exit 1
 ;;
esac

# create unexpired encryption subkeys for card
{
  printf '%s\n' \
   "%no-ask-passphrase" \
   "%no-protection" \
   "addkey"
  case "${LEGACY_SUBKEYING}" in
   true)
    printf '%s\n' \
     "rsa/e" \
     "4096"
   ;;
   *)
    printf '%s\n' \
     "ecc/e" \
     "curve25519"
   ;;
  esac
  printf '%s\n' \
   "${GPG_SUBKEY_EXPIRY}" \
   "save"
} | my_gpg --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}"

# ditto authentication - which _needs_ to be RSA for codecommit, sorry.
{
  printf '%s\n' \
   "%no-ask-passphrase" \
   "%no-protection" \
   "addkey"
  case "${LEGACY_SUBKEYING}${SIGN_AS_AUTH2}" in
   falsefalse|true*)
    printf '%s\n' \
     'rsa/*' \
     "=a" \
     "4096"
   ;;
   falsetrue)
    printf '%s\n' \
     'ecc/*' \
     "=a" \
     "curve25519"
  esac
  printf '%s\n' \
   "${GPG_SUBKEY_EXPIRY}" \
   "save"
} | my_gpg --expert --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}"
# + printf '%s\n' %no-ask-passphrase %no-protection addkey 'rsa/*' =a 4096 18m save

# and signing (or, alternate auth!)
{
  printf '%s\n' \
   "%no-ask-passphrase" \
   "%no-protection" \
   "addkey"
  case "${LEGACY_SUBKEYING}${SIGN_AS_AUTH2}" in
   truefalse)
    printf '%s\n' \
     "rsa/s" \
     "4096"
   ;;
   truetrue|falsetrue)
    printf '%s\n' \
     'rsa/*' \
     "=a" \
     "4096"
   ;;
   falsefalse)
    printf '%s\n' \
     "ecc/s" \
     "curve25519"
   ;;
  esac
  printf '%s\n' \
   "${GPG_SUBKEY_EXPIRY}" \
   "save"
} | my_gpg --expert --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}"

# if we're using password store, dump *the entire key* there.
[[ -n "${PASS_ITEM}" ]] && {
  my_gpg --export-secret-keys "${GPG_EMAIL}" | pass insert -m -f "${PASS_ITEM}"
}

# so, the theory here is we'll order subkeys and load by expiry - the first export contains the last to expire
# and types s/e/a. the second blob contains the next e/a keys. the c key doesn't get exported until we backup the
# whole thing.

# track loaded keys here
one=()  # reformed key handles for gpg export call

for l in e s a ; do
  _scratch=""
  _scratch="$(my_gpg --list-keys --with-colons "${GPG_EMAIL}" | \
     grep 'sub:u:[4096|255]' | grep "${l}:::::" | \
     gawk -F: '{ key[$7NR]=$5 } END { asort(key) ; if (key[1]) { printf "0x%s!\n", key[1] } }')"
  [[ -n "${_scratch}" ]] && one=( "${one[@]}" "${_scratch}" )
done

# if we have 2 authentication keys, we need to...find the other one.
[[ "${SIGN_AS_AUTH2}" == "true" ]] && {
  one=("${one[@]}"
      "$(my_gpg --list-keys --with-colons "${GPG_EMAIL}" \
         grep 'sub:u:[4096|255]' | grep "a:::::" | \
         gawk -F: '{ key[$7NR]=$5 } END { asort(key) ; if (key[2]) { printf "0x%s!\n", key[2] } }')"
  )
}

certgrip="0x$(my_gpg --list-keys --with-colons "${GPG_EMAIL}" | \
           grep 'pub:u:[4096|255]' | \
           gawk -F: '{ print $5 }')!"

# export the certifying key to a file in pwd if we made that.
[[ "${_made_master}" -eq 1 ]] && my_gpg --export-secret-keys -a "${certgrip}" > "${GPG_EMAIL}-certify.asc"

# export the secret subkeys to our scratch dir
my_gpg --export-secret-subkeys -a "${one[@]}" > "${sc_temp}/${GPG_EMAIL}-redone.asc"

# drive _another_ gpg to wire up the card.
cardkeydir=$(mktemp -d)
cardgpg () { GNUPGHOME="${cardkeydir}" gpgwrap "${@}" ; }
# import the certifying key to _this_ gpg
my_gpg --export-secret-keys -a "${certgrip}" | cardgpg --import
# echo 'reader-port "Yubico Yubikey NEO OTP+U2F+CCID 01 00"' > scratch/scdaemon.conf
cardgpg --import "${sc_temp}/${GPG_EMAIL}-redone.asc"
cardgpg --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}" << TRUST
trust
5
y
save
TRUST

# we need to actually get the order the subkeys were written in for card writing
ekey=$(cardgpg --list-keys --with-colons 2>/dev/null | grep 'sub:u:' | grep -n ':e:::::')
ekey=${ekey:0:1}
akey=$(cardgpg --list-keys --with-colons 2>/dev/null | grep 'sub:u:' | grep -n ':a:::::')
akey=${akey:0:1}
skey=$(cardgpg --list-keys --with-colons 2>/dev/null | grep 'sub:u:' | grep -n ':s:::::')
skey=${skey:0:1}

# if we are using sign as auth2, we're going to prefer the rsa key as auth, and the ecc key
# as sign - but they're both auth keys for gpg.
[[ "${SIGN_AS_AUTH2}" == "true" ]] && {
  akey=$(cardgpg --list-keys --with-colons 2>/dev/null | grep 'sub:u:' | grep -n ':a::::::23:')
  akey=${akey:0:1}
  skey=$(cardgpg --list-keys --with-colons 2>/dev/null | grep 'sub:u:' | grep -n ':a:::::ed25519::')
  skey=${skey:0:1}
}

# now that we know which key is which, push to card. you will be prompted for the admin pin.
# unless it doesn't work, which on the older cards seems *way* flakier.
# highly recommend you use the password store option and then poke at it by hand.
printf '%s\n' 'toggle' "key ${skey}" 'keytocard' '1' 'save' '' | \
 cardgpg --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}"

printf '%s\n' 'toggle' "key ${ekey}" 'keytocard' '2' 'save' '' | \
 cardgpg --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}"

printf '%s\n' 'toggle' "key ${akey}" 'keytocard' '3' 'save' '' | \
 cardgpg --edit-key --batch --command-fd 0 --passphrase '' "${GPG_EMAIL}"

# export the resulting stubby key
cardgpg --export-secret-subkeys "${GPG_EMAIL}" > "${GPG_EMAIL}-new_subkeys.gpg"

ekey=""
akey=""

pubkeys=()

# and grab all the other keys
for l in $(cardgpg --list-keys --with-colons|grep 'sub:u:'|cut -d: -f5,12 | grep -E '(a|s)$') ; do
  pubkeys=("${pubkeys[@]}" "0x${l%:*}!")
done

# export to pwd for upload-ability
cardgpg --export -a "${pubkeys[@]}" > "${GPG_EMAIL}-upload.asc"
