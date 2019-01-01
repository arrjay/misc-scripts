#!/usr/bin/env bash

# take a password store item and coerce it into 1password json for the op tool
[ "${1:-}" ] || { echo "password store entity required" 1>&2 ; exit 1 ; }
pass_store_ent="${1}"

# read password from pass and spit out a json template for op tool. use jq to handle any needed encoding.

# we use the last element of the password path as the title of the 1password entity
title="$(basename "${pass_store_ent}")"

# read password store data
# this loop assumes the first line is password data, otp URIs are stored raw (pass-otp compatible)
# and everything else is a colon(-space) delimited entity
ct=0
keys=()
values=()
pw=''
username=''
otp=''
while read -r line ; do
  # first, check if otp line, the password line, then read as k-v line
  case "${line}" in
    otpauth://*) otp="${line}" ;;
    *) 
      if [ "${ct}" == 0 ] ; then
        pw="${line}"
      else
        # we use substring globbing to handle _the first_ colon delim, as more could be in the password.
        keys["${ct}"]="${line%%:*}"
        values["${ct}"]="${line#"${keys["${ct}"]}":}"
        # next, replace the key with a lowercase version of itself.
        keys["${ct}"]="${keys["${ct}"],,}"
        # then, if the very first character of the value is a space, remove that
        case "${values["${ct}"]}" in
         " "*) values["${ct}"]="${values["${ct}"]:1}" ;;
        esac
      fi
      ;;
  esac
  ct=$((ct+1))
done < <(pass ls "${1}")

# check if we have a user/username key - those get Login templates
_temp_ct=0
while [ "${_temp_ct}" -lt "${ct}" ] ; do
  case "${keys["${_temp_ct}"]}" in
    user|username)
      username="${values["${_temp_ct}"]}"
      # if we matched, we scrub the k/v pair
      keys["${_temp_ct}"]=''
      values["${_temp_ct}"]=''
    ;;
  esac
  _temp_ct=$((_temp_ct+1))
done

# similar deal to grab a URL
_temp_ct=0
while [ "${_temp_ct}" -lt "${ct}" ] ; do
  case "${keys["${_temp_ct}"]}" in
    url|website)
      url="${values["${_temp_ct}"]}"
      # if we matched, we scrub the k/v pair
      keys["${_temp_ct}"]=''
      values["${_temp_ct}"]=''
  esac
  _temp_ct=$((_temp_ct+1))
done

# figure out what item type we are creating
itemtype='password'
[ -n "${username:-}" ] && itemtype='login'

# the templates are hardcoded here. sorry.
# the brace group is about to feed this *into* op
op_create_args=("${itemtype}" "--title=${title}")

# the urls are set here as an argument to op create itself...
[ -n "${url:-}" ] && op_create_args=("${op_create_args[@]}" "--url=${url}")

# if we want a vault other than private, use the OP_VAULT_NAME envvar.
[ -n "${OP_VAULT_NAME:-}" ] && op_create_args=("${op_create_args[@]}" "--vault=${OP_VAULT_NAME}")

op create item "${op_create_args[@]}" "$({
#echo "$(
  # preamble
  cat << _EOS_
{
  "notesPlain": "",
  "passwordHistory": [],
_EOS_
  # if we have an otp code, replace the sections block.
  if [ -n "${otp:-}" ] ; then
cat << _EOS_
  "sections": [
    {
      "name": "linked items",
      "title": "Related Items"
    },
    {
      "fields": [
        {
          "k": "concealed",
          "n": "TOTP_$(apg -M NC -m 32 -a1 -E abcdefghijklmnopqrstuvwxyzGHIJKLMNOPQRSTUVWXYZ |head -n1)",
          "t": "one-time-password",
          "v": $(echo "${otp}"|jq -R .)
        }
      ],
      "name": "Section_$(apg -M NC -m 32 -a1 -E abcdefghijklmnopqrstuvwxyzGHIJKLMNOPQRSTUVWXYZ |head -n1)"
    }
  ],
_EOS_
  else
cat << _EOS_
  "sections": [],
_EOS_
  fi
  # jump around dependent on template type
  case "${itemtype}" in
    login)
      cat << _EOS_
  "fields": [
    {
      "value": $(echo "${username}"|jq -R .),
      "name": "username",
      "type": "T",
      "designation": "username"
    },
    {
      "value": $(echo "${pw}"|jq -R .),
      "name": "password",
      "type": "P",
      "designation": "password"
    }
  ]
_EOS_
    ;; # login itemtype
    password)
      cat << _EOS_
  "password": $(echo "${pw}"|jq -R .)
_EOS_
    ;; # password itemtype
  esac

# footer
cat << _EOS_
}
_EOS_
# _that_ was then encoded as a shell argument to op create.
} | op encode)"
#)"
