#!/bin/bash

function read_presets {
  [ -z "$1" ] && return
  if [ ! -e "$1" ]; then
    echo "no such file or diretory: $preset"
    exit 2
  fi
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
  default=( "countryName" "stateOrProvinceName" "localityName" "organizationName" "organizationalUnitName" "emailAddress" "commonName" "policy")
  list=("${default[@]}" "${@}")
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
  [ -z $crlUrl ] && export crlUrl="www.example.com" || export crlUrl="$crlUrl"
  [ -z $policy ] && export policy="policy_loose"
}

function export_ca_dir {
  export ca_dir="$1"
}

function insert_san_to_cnf {
  cnf=$1
  name=$2
  san="${3:-DNS}"

  tmp_cnf="${name}-tmp.cnf"
  cp $1 ./$tmp_cnf
  count=1
  while true; do
    dns="altName$count"
    eval "val=\$$dns"
    [ -z "$val" ] && break
    count=$(( count + 1 ))
    echo "$san.${count} = $val" >> $tmp_cnf
  done
  echo "$tmp_cnf"
}

function extract_san_from_csr {
  cnf=$1
  name=$2
  csr=$3
  san="${4:-DNS}"

  tmp_cnf="${name}-tmp.cnf"
  cp $cnf ./$tmp_cnf
  list=`grep DNS $csr | sed -e 's/DNS:/\n/g' | sed 's/,//g'`
  count=0
  for dns in $list; do
    echo "$san.$count = $dns" >> $tmp_cnf
    count=$(( count + 1 ))
  done
  echo "$tmp_cnf"
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
