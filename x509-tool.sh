#!/bin/bash

# set validation times
ca_days=7300
intm_days=1825

# set key lengths
ca_bits=8192
intm_bits=4096
srv_bits=2048
client_bits=2048

# openssl config files
ca_cnf="ca.cnf"
intm_cnf="intermediate.cnf"
srv_cnf="server.cnf"
client_cnf="client.cnf"

# set default for all options
default_ca_dir="root-ca"
default_intm_dir="intermediate-ca"
default_srv_dir="server"
default_client_dir="client"

# args
batch_mode="-batch"

# use as random generator
rand="openssl rand -hex 8"

function show_usage {
  echo "Usage: $0 [<options>] <command> <subcommand> "
  echo "  commands:"
  echo "    create ca                     create root ca"
  echo "    create intermediate <name>    create intermediate ca"
  echo "    create server|client <name>   create server or client certifacte:"
  echo "    update server|client <name>   export end-user certificate"
  echo "    revoke intermediate           revoke intermediate certificate"
  echo "    revoke server|client <name>   revoke server or client certificate"
  echo "    update ca|intermediate        update revocation list:"
  echo ""
  echo "  options:"
  echo "      -p/--preset <file>          load presets from file"
  echo "      -i/--interactive            load presets from file"
  echo "      -b/--bits <number>          set key length"
  echo "      -a/--authority <path>       use sepecific ca authority"
  echo "      --authpassphrase <pw>       passphrase for private key of authority"
  echo "      --passphrase <pw>           set passphrase for private key"
  echo "      --ca-cnf <file>             openssl config for root-ca"
  echo "      --intermediate-cnf <file>   penssl config for intermediate-ca"
  echo "      --server-cnf <file>         openssl config for server certificates"
  echo "      --client-cnf <file>         openssl config for client certificates"
  echo "      ---pkcs12 <pw>              export client/server certs to pkcs12 file"
  echo "      -KEY=VALUE                  C/ST/L/O/OU/CN/@(mail)/DNS"

}

if [ $# -eq 0 ]; then
  show_usage
  exit 1
fi

subjaltname_count=0
# parse args
while [ "$1" != "" ]; do
  PARAM=`echo $1 | awk -F= '{print $1}'`
  VALUE=`echo $1 | awk -F= '{print $2}'`
  case $PARAM in
    -p | --preset)
      preset=$2 && shift
      ;;
    -i | --interactive)
      batch_mode=""
      ;;
    -a | --authority)
      auth_dir=$2 && shift
      ;;
    --authpassphrase)
      auth_pw=$2 && shift
      auth_passin="-passin pass:$auth_pw"
      ;;
    --ca-cnf)
      ca_cnf=$2 && shift
      ;;
    --intermediate-cnf)
      intermediate_cnf=$2 && shift
      ;;
    --server-cnf)
      srv_cnf=$2 && shift
      ;;
    --client-cnf)
      client_cnf=$2 && shift
      ;;
    --passphrase)
      pw=$2 && shift
      passout="-passout pass:$pw"
      passin="-passin pass:$pw"
      ;;
    --pkcs12)
      pkcs12=$2 && shift
      ;;
    -C)
      countryName=$VALUE
      ;;
    -ST)
      stateOrProvinceName=$VALUE
      ;;
    -L)
      localityName=$VALUE
      ;;
    -O)
      organizationName=$VALUE
      ;;
    -OU)
      organizationalUnitName=$VALUE
      ;;
    -CN)
      commonName=$VALUE
      ;;
    -@)
      emailAddress=$VALUE
      ;;
    -DNS)
      export "altName$subjaltname_count=$VALUE"
      subjaltname_count=$(( subjaltname_count + 1 ))
      ;;
    -b | --bits)
      bits=$2 && shift
      ;;
    -h | --help)
      show_usage && exit 0
      ;;
    -*)
      echo "ERROR: unknown parameter \"$PARAM\"" && exit 1
      ;;
    *)
      break
      ;;
  esac
  shift
done


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

function cont {
  if [ $1 -ne 0 ]; then
    prompt "-----------------"
    prompt "An error occurred" red
    prompt "-----------------"
    exit $1
  fi
}

function main {
  action=$1 && shift
  read_presets
  case "$action" in
    create)
      create $*
      ;;
    revoke)
      revoke $*
      ;;
    update)
      update $*
      ;;
    export)
      export_pkcs12 $*
      ;;
    *)
      echo "ERROR: unknown action \"$action\" for main" && exit 1
  esac
}

function create {
  type=$1 && shift
  case "$type" in
    ca)
      create_ca $*
      ;;
    intermediate)
      create_intermediate $*
      ;;
    server)
      create_server $*
      ;;
    client)
      create_client $*
      ;;
    *)
      echo "ERROR: unknown type \"$type\" for create" && exit 1
  esac
}

function revoke {
  type=$1 && shift
  case "$type" in
    intermediate)
      revoke_intermediate
      ;;
    server)
      revoke_server $*
      ;;
    client)
      revoke_client $*
      ;;
    *)
      echo "ERROR: unknown type \"$type\" for revoke" && exit 1
  esac
}

function update {
  type=$1 && shift
  case "$type" in
    ca)
      update_ca_crl
      ;;
    intermediate)
      update_intermediate_crl
      ;;
    *)
      echo "ERROR: unknown type \"$type\" for update" && exit 1
  esac
}

function create_ca {
  name=$1
  [ -z "$name" ] || intm_dir="$name-ca"
  ca_dir="${ca_dir:-$default_ca_dir}"
  bits="${bits:-$ca_bits}"
  days="${days:-$ca_days}"

  attribs=( "countryName" "stateOrProvinceName" "localityName" \
    "organizationName" "organizationalUnitName" "emailAddress" "commonName")
  for attrib in "${attribs[@]}"; do
    eval "val=\$$attrib"
    if [ -z "$val" ]; then
      echo "missing attribute $attrib" && exit 2
    else
      export "$attrib=$val"
    fi
  done

  # create root-ca folders
  mkdir -p $ca_dir/
  mkdir -p $ca_dir/certs $ca_dir/crl $ca_dir/newcerts $ca_dir/csr $ca_dir/private
  chmod 700 $ca_dir/private
  touch $ca_dir/index.txt
  # workaround for "Can't open $ca_dir/index.txt.attr for reading, No such file or directory"
  touch $ca_dir/index.txt.attr
  $rand > $ca_dir/serial
  $rand > $ca_dir/crlnumber

  # link openssl config file
  cd $ca_dir && ln -s "../$ca_cnf" "openssl.cnf" && cd - >/dev/null

  # create root-CA private key:
  prompt "creating root private key"
  openssl genrsa -aes256 $passout -out $ca_dir/private/ca-key.pem $bits
  cont $?

  # create root certificate
  prompt "creating root certificate"
  openssl req $batch_mode -config $ca_cnf -key $ca_dir/private/ca-key.pem $passin -new -x509 -days $days -extensions v3_ca -out $ca_dir/certs/ca-cert.pem
  cont $?

  chmod 400 $ca_dir/private/ca-key.pem

  prompt "exporting root certificate"
  openssl x509 -outform der -in $ca_dir/certs/ca-cert.pem -out $ca_dir/certs/ca-cert.crt
  echo "$ca_dir/certs/ca-cert.crt"
  openssl x509 -noout -text -in $ca_dir/certs/ca-cert.pem > $ca_dir/certs/ca-cert.txt
  echo "$ca_dir/certs/ca-cert.txt"
  chmod 444 $ca_dir/certs/ca-cert.*

  update_ca_crl $name

  prompt "link certificate as chain"
  cd $ca_dir/certs && ln -s ca-cert.pem certificate-chain.pem && cd - >/dev/null
  echo "$ca_dir/certs/certificate-chain.pem"
  cd $ca_dir/certs && ln -s ca-cert.crt certificate-chain.crt && cd - >/dev/null
  echo "$ca_dir/certs/certificate-chain.crt"

}

function update_ca_crl {
  name=$1
  [ -z "$name" ] || ca_dir="$name-ca"
  prompt "updating root-ca revocation list"
  openssl ca $batch_mode -config $ca_cnf $passin -gencrl -out $ca_dir/crl/ca-crl.pem
  cont $?
  echo "$ca_dir/crl/ca-crl.pem"
  openssl crl -in $ca_dir/crl/ca-crl.pem -noout -text > $ca_dir/crl/ca-crl.txt
  echo "$ca_dir/crl/ca-crl.txt"
}


function create_intermediate {
  name=$1
  [ -z "$name" ] || intm_dir="$name-ca"
  intm_dir="${intm_dir:-$default_intm_dir}"
  auth_dir="${auth_dir:-$default_ca_dir}"
  bits="${bits:-$intm_bits}"
  days="${days:-$intm_days}"

  attribs=( "countryName" "stateOrProvinceName" "localityName" \
    "organizationName" "organizationalUnitName" "emailAddress" "commonName")
  for attrib in "${attribs[@]}"; do
    eval "val=\$$attrib"
    if [ -z "$val" ]; then
      echo "missing attribute $attrib" && exit 2
    else
      export "$attrib=$val"
    fi
  done

  # create intermediate folder
  mkdir -p $intm_dir
  mkdir -p $intm_dir/certs $intm_dir/crl $intm_dir/newcerts $intm_dir/csr $intm_dir/private
  chmod 700 $intm_dir/private
  touch $intm_dir/index.txt
  # workaround for "Can't open $intm_dir/index.txt.attr for reading, No such file or directory"
  touch $intm_dir/index.txt.attr
  $rand > $intm_dir/serial
  $rand > $intm_dir/crlnumber

  # link openssl config file
  cd $intm_dir && ln -s "../$intm_cnf" "openssl.cnf" && cd - >/dev/null

  # create intermediate private key
  prompt "creating intermediate private key"
  openssl genrsa -aes256 $passout -out $intm_dir/private/intermediate-key.pem $bits
  cont $?

  # create and sign intermediate certificate
  prompt "creating intermediate certificate"
  openssl req $batch_mode -config $intm_cnf -key $intm_dir/private/intermediate-key.pem $passin -new -out $intm_dir/csr/intermediate-csr.pem
  cont $?

  prompt "signing intermediate certificate"
  openssl ca $batch_mode -config $ca_cnf $auth_passin -days $days -extensions v3_intermediate_ca -notext -in $intm_dir/csr/intermediate-csr.pem -out $intm_dir/certs/intermediate-cert.pem
  cont $?

  chmod 400 $intm_dir/private/intermediate-key.pem

  prompt "exporting intermediate certificate"
  openssl x509 -noout -text -in $intm_dir/certs/intermediate-cert.pem > $intm_dir/certs/intermediate-cert.txt
  echo "$intm_dir/certs/intermediate-cert.txt"
  chmod 444 $intm_dir/certs/intermediate-cert.*

  update_intermediate_crl $name

  prompt "creating certificate chain"
  cat $auth_dir/certs/ca-cert.pem $intm_dir/certs/intermediate-cert.pem > $intm_dir/certs/certificate-chain.pem
  echo "$intm_dir/certs/certificate-chain.pem"
  openssl x509 -outform der -in $intm_dir/certs/certificate-chain.pem -out $intm_dir/certs/certificate-chain.crt
  echo "$intm_dir/certs/certificate-chain.crt"
}

function update_intermediate_crl {
  name=$1
  [ -z "$name" ] || intm_dir="$name-ca"
  prompt "updating certificate revocation list"
  openssl ca $batch_mode -config $intm_cnf $passin -gencrl -out $intm_dir/crl/intermediate-crl.pem
  cont $?
  echo "$intm_dir/crl/intermediate-crl.pem"
  openssl crl -in $intm_dir/crl/intermediate-crl.pem -noout -text > $intm_dir/crl/intermediate-crl.txt
  echo "$intm_dir/crl/intermediate-crl.pem"
}

function revoke_intermediate {
  name=$1
  [ -z "$name" ] || intm_dir="$name-ca"
  prompt "revoking intermediate certificate"
  openssl ca $batch_mode -config $ca_cnf -revoke $intm_dir/certs/intermediate-cert.pem
  cont $?
  update_ca_crl
}

function create_server {
  name=$1
  srv_dir="${srv_dir:-$default_srv_dir}"
  auth_dir="${auth_dir:-$default_ca_dir}"
  auth_cnf="$auth_dir/openssl.cnf"
  bits="${bits:-$intm_bits}"
  days="${days:-$intm_days}"
  export commonName="$name"
  export altName="$name"

  mkdir -p $srv_dir/certs $srv_dir/private
  chmod 700 $srv_dir/private
  prompt "creating private key for $name"
  openssl genrsa -out $srv_dir/private/$name-key.pem $bits
  cont $?

  prompt "creating server certificate for $name"
  openssl req $batch_mode -config $srv_cnf -key $srv_dir/private/$name-key.pem $passin -new -out $auth_dir/csr/$name-csr.pem
  cont $?

  prompt "inspecting server certificate request for $name"
  openssl asn1parse -inform PEM -in $auth_dir/csr/$name-csr.pem > $auth_dir/csr/$name-csr.txt
  echo "$auth_dir/csr/$name-csr.txt"
  tmp_cnf="${name}-tmp.cnf"
  cp $auth_cnf ./$tmp_cnf
  # extract subjectAltNames from csr file and append it to the configuration
  sed -n '/X509v3 Subject Alternative Name/{n;p;}' $auth_dir/csr/$name-csr.txt | awk '{ print "DNS." ++count[$6] " = " substr($7,2) }' >> $tmp_cnf

  prompt "signing server certificate for $name"
  openssl ca $batch_mode -config $tmp_cnf $auth_passin -policy policy_moderate -extensions server_cert -notext -md sha256 -in $auth_dir/csr/$name-csr.pem -out $srv_dir/certs/$name-cert.pem
  cont $?
  rm $tmp_cnf

  chmod 400 $srv_dir/private/$name-key.pem

  convert_certs $srv_dir $name
  [ -z $pkcs12 ] || export_pkcs12 $srv_dir $name
}

function revoke_server {
  name=$1
  prompt "revoking server certificate for $name"
  openssl ca $batch_mode -config $intm_cnf -revoke $srv_dir/certs/$name-cert.pem
  cont $?
  update_intermediate_crl
}

function create_client {
  name=$1
  bits="${bits:-$client_bits}"
  mkdir -p $client_dir/certs $client_dir/private
  prompt "creating private key for $name"
  openssl genrsa -out $client_dir/private/$name-key.pem $bits
  cont $?

  prompt "creating client certificate for $name"
  openssl req $batch_mode -config $client_cnf -new -key $client_dir/private/$name-key.pem -out $intm_dir/csr/$name-csr.pem
  cont $?

  prompt "signing client certificate for $name"
  openssl ca $batch_mode -config $intm_cnf -policy policy_loose -extensions client_cert -notext -md sha256 -in $intm_dir/csr/$name-csr.pem -out $client_dir/certs/$name-cert.pem
  cont $?

  chmod 400 $client_dir/private/$name-key.pem

  convert_certs $client_dir $name
  [ -z $pkcs12 ] || export_pkcs12 $srv_dir $name
}

function revoke_client {
  name=$1
  prompt "revoking client certificate for $name"
  openssl ca $batch_mode -config $intm_cnf -revoke $client_dir/certs/$name-cert.pem
  cont $?
  update_intermediate_crl
}

function convert_certs {
  dir=$1
  name=$2
  prompt "converting certificate to CRT and Text"
  openssl x509 -outform der -in $dir/certs/$name-cert.pem -out $dir/certs/$name-cert.crt
  echo "$dir/certs/$name-cert.crt"
  openssl x509 -noout -text -in $dir/certs/$name-cert.pem > $dir/certs/$name-cert.txt
  echo "$dir/certs/$name-cert.txt"
}

function export_pkcs12 {
  dir=$1
  name=$2
  auth_dir="${auth_dir:-$default_ca_dir}"

  prompt "exporting to pkcs12 format (pw: '$pkcs12')"
  openssl pkcs12 -export -passout pass:$pkcs12 -inkey $dir/private/$name-key.pem -in $dir/certs/$name-cert.pem -certfile $auth_dir/certs/certificate-chain.pem -out $dir/$name.p12
  cont $?
  echo "$dir/$name.p12"
}

main $*
