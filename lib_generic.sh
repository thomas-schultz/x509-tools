#!/bin/bash

function read_presets {
  [ -e "$preset" ] || return
  while IFS="=" read -r line; do
    if [ -z "$line" ] || [[ "$line" =~ ^\#.* ]]; then
      continue
    fi
    KEY=`echo "$line" | awk -F "=" '{print $1}' | awk '{gsub(/^ +| +$/,"")} {print $0}'`
    VAL=`echo "$line" | awk -F "=" '{print $2}' | awk '{gsub(/^ +| +$/,"")} {print $0}'`
    [ -z $KEY ] && continue
    export "$KEY=$VAL"
  done < $preset
}

function prompt {
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  LGRAY='\033[1;37m'
  NONE='\033[0m'
  if [ -z "$2" ]; then
    COLOR=$LGRAY
  else
    case $2 in
      "red")
        COLOR=$RED;;
      "green")
        COLOR=$GREEN;;
      *)
        COLOR=$NONE;;
    esac
  fi
  echo -e "${COLOR}$1${NONE}"
}

function puts {
  [ -z $verbose ] || echo "$1"
  return
}

function cont {
  if [ $1 -ne 0 ]; then
    prompt "An error occurred, exited with code $1" red
    exit $1
  fi
}

function export_params {
  list=("${@}")
  for param in "${list[@]}"; do
    eval "val=\$$param"
    if [ -z "$val" ] && [ -z $batch_mode ]; then
      export "$param="
    elif [ -z "$val" ]; then
      echo "missing attribute $param" && exit 2
    else
      export "$param=$val"
    fi
  done
  if [ -z $crlUrl ]; then
    export crlUrl="www.example.com"
  else
    export "crlUrl=$crlUrl"
    crlPoint="-extensions crl_ext"
  fi
}

function export_cnf {
  export ca_name="$1"
  export ca_dir="$2"
}

function convert_certs {
  dir=$1
  name=$2
  prompt "converting certificate to CRT and Text"
  openssl x509 -outform der -in $dir/certs/$name-cert.pem -out $dir/certs/$name-cert.crt
  puts "$dir/certs/$name-cert.crt"
  openssl x509 -noout -text -in $dir/certs/$name-cert.pem > $dir/certs/$name-cert.txt
  puts "$dir/certs/$name-cert.txt"
}
