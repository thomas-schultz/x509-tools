#!/bin/bash

ca_cnf="ca.cnf"
intm_cnf="intermediate.cnf"
srv_cnf="server.cnf"
client_cnf="client.cnf"

ca_dir="root-ca"
intm_dir="intermediate-ca"
srv_dir="server"
client_dir="client"

ca_days=7300
ca_bits=8192
intm_bits=4096
srv_bits=2048
client_bits=2048

# uncomment if a Intermediate-CA should be used
#use_intermediate="yes"

rand="openssl rand -hex 8"

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

function main {
  action=$1
  shift
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
    show_help
  esac
}

function create {
  type=$1
  shift
  case "$type" in
  ca)
    create_ca
    ;;
  intermediate)
    create_intermediate
    ;;
  server)
    create_server $*
    ;;
  client)
    create_client $*
    ;;
  *)
    show_help
  esac
}

function revoke {
  type=$1
  shift
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
    show_help
  esac
}

function update {
  type=$1
  shift
  case "$type" in
  ca)
    update_ca_crl
    ;;
  intermediate)
    update_intermediate_crl
    ;;
  *)
    show_help
  esac
}


function show_help {
  echo "Usage: $0"
  echo "  create root or intermediate ca:"
  echo "    create ca|intermediate"
  echo "  create server or client certifacte:"
  echo "    create server|client <name> [<options>]"
  echo "      --pkcs12  export to pkcs12 file"
  echo "  export end-user certificate"
  echo "    update server|client <name>"
  echo "  revoke certificate:"
  echo "    revoke intermediate"
  echo "    revoke server|client <name>"
  echo "  update revocation list:"
  echo "    update ca|intermediate"
  exit 1
}

function create_ca {
  # create root-ca folders
  mkdir -p $ca_dir/
  mkdir -p $ca_dir/certs $ca_dir/crl $ca_dir/newcerts $ca_dir/csr $ca_dir/private
  chmod 700 $ca_dir/private
  touch $ca_dir/index.txt
  # workaround for "Can't open $ca_dir/index.txt.attr for reading, No such file or directory"
  touch $ca_dir/index.txt.attr
  $rand > $ca_dir/serial
  $rand > $ca_dir/crlnumber

  # create root-CA private key:
  prompt "creating root private key"
  openssl genrsa -aes256 -out $ca_dir/private/ca-key.pem $ca_bits
  cont $?

  # create root certificate
  prompt "creating root certificate"
  openssl req -config $ca_cnf -key $ca_dir/private/ca-key.pem -new -x509 -days $ca_days -extensions v3_ca -out $ca_dir/certs/ca-cert.pem
  cont $?

  chmod 400 $ca_dir/private/ca-key.pem

  prompt "exporting root certificate"
  openssl x509 -outform der -in $ca_dir/certs/ca-cert.pem -out $ca_dir/certs/ca-cert.crt
  echo "$ca_dir/certs/ca-cert.crt"
  openssl x509 -noout -text -in $ca_dir/certs/ca-cert.pem > $ca_dir/certs/ca-cert.txt
  echo "$ca_dir/certs/ca-cert.crt"
  chmod 444 $ca_dir/certs/ca-cert.*

  update_ca_crl
}

function update_ca_crl {
  prompt "updating root-ca revocation list"
  openssl ca -config $ca_cnf -gencrl -out $ca_dir/crl/ca-crl.pem
  echo "$ca_dir/crl/ca-crl.pem"
  openssl crl -in $ca_dir/crl/ca-crl.pem -noout -text > $ca_dir/crl/ca-crl.txt
  echo "$ca_dir/crl/ca-crl.txt"
}


function create_intermediate {
  if [ -z $use_intermediate ]; then
    prompt "intermediate certificate is diabled" red
    exit 2
  fi
  # create intermediate folder
  mkdir -p $intm_dir
  mkdir -p $intm_dir/certs $intm_dir/crl $intm_dir/newcerts $intm_dir/csr $intm_dir/private
  chmod 700 $intm_dir/private
  touch $intm_dir/index.txt
  # workaround for "Can't open $intm_dir/index.txt.attr for reading, No such file or directory"
  touch $intm_dir/index.txt.attr
  $rand > $intm_dir/serial
  $rand > $intm_dir/crlnumber

  # create intermediate private key
  prompt "creating intermediate private key"
  openssl genrsa -aes256 -out $intm_dir/private/intermediate-key.pem $intm_bits
  cont $?

  # create and sign intermediate certificate
  prompt "creating intermediate certificate"
  openssl req -config $intm_cnf -new -key $intm_dir/private/intermediate-key.pem -out $intm_dir/csr/intermediate-csr.pem
  cont $?

  prompt "signing intermediate certificate"
  openssl ca -config $ca_cnf -extensions v3_intermediate_ca -notext -in $intm_dir/csr/intermediate-csr.pem -out $intm_dir/certs/intermediate-cert.pem
  cont $?

  chmod 400 $intm_dir/private/intermediate-key.pem

  prompt "exporting intermediate certificate"
  openssl x509 -noout -text -in $intm_dir/certs/intermediate-cert.pem > $intm_dir/certs/intermediate-cert.txt
  echo "$intm_dir/certs/intermediate-cert.txt"
  chmod 444 $intm_dir/certs/intermediate-cert.*

  update_intermediate_crl

  prompt "creating cerificate chain"
  cat $ca_dir/certs/ca-cert.pem $intm_dir/certs/intermediate-cert.pem > $intm_dir/certs/intermediate-chain.pem
  echo "$intm_dir/certs/intermediate-chain.pem"
  openssl x509 -outform der -in $intm_dir/certs/intermediate-chain.pem -out $intm_dir/certs/intermediate-chain.crt
  echo "$intm_dir/certs/intermediate-chain.crt"
}

function update_intermediate_crl {
  if [ -z $use_intermediate ]; then
    update_ca_crl
  fi
  prompt "updating certificate revocation list"
  openssl ca -config $intm_cnf -gencrl -out $intm_dir/crl/intermediate-crl.pem
  cont $?
  openssl crl -in $intm_dir/crl/intermediate-crl.pem -noout -text > $intm_dir/crl/intermediate-crl.txt
  echo "$intm_dir/crl/intermediate-crl.pem"
}

function revoke_intermediate {
  if [ -z $use_intermediate ]; then
    prompt "intermediate certificate is diabled" red
    exit 2
  fi
  name=$1
  prompt "revoking intermediate certificate"
  openssl ca -config $ca_cnf -revoke $intm_dir/certs/intermediate-cert.pem
  cont $?
  update_ca_crl
}

function create_server {
  name=$1
  mkdir -p $srv_dir/certs $srv_dir/private
  chmod 700 $srv_dir/private
  prompt "creating private key for $name"
  openssl genrsa -out $srv_dir/private/$name-key.pem $srv_bits
  cont $?

  prompt "creating server certificate for $name"
  openssl req -config $srv_cnf -new -key $srv_dir/private/$name-key.pem -out $intm_dir/csr/$name-csr.pem
  cont $?

  prompt "inspecting server certificate request for $name"
  openssl asn1parse -inform PEM -in $intm_dir/csr/$name-csr.pem > $intm_dir/csr/$name-csr.txt
  echo "$intm_dir/csr/$name-csr.txt"
  new_config=${name}-${intm_cnf}
  cp $intm_cnf $new_config
  # extract subjectAltNames from csr file and append it to the configuration
  sed -n '/X509v3 Subject Alternative Name/{n;p;}' $intm_dir/csr/$name-csr.txt | awk '{ print "DNS." ++count[$6] " = " substr($7,2) }' >> $new_config

  prompt "signing server certificate for $name"
  openssl ca -config $new_config -extensions server_cert -notext -md sha256 -in $intm_dir/csr/$name-csr.pem -out $srv_dir/certs/$name-cert.pem
  cont $?
  rm $new_config

  chmod 400 $srv_dir/private/$name-key.pem

  convert_certs $srv_dir $name
  if [ "$2" == "--pkcs12" ]; then
    export_pkcs12 $srv_dir $name
  fi
}

function revoke_server {
  name=$1
  prompt "revoking server certificate for $name"
  openssl ca -config $intm_cnf -revoke $srv_dir/certs/$name-cert.pem
  cont $?
  update_intermediate_crl
}

function create_client {
  name=$1
  mkdir -p $client_dir/certs $client_dir/private
  prompt "creating private key for $name"
  openssl genrsa -out $client_dir/private/$name-key.pem $client_bits
  cont $?

  prompt "creating client certificate for $name"
  openssl req -config $client_cnf -new -key $client_dir/private/$name-key.pem -out $intm_dir/csr/$name-csr.pem
  cont $?

  prompt "signing client certificate for $name"
  openssl ca -config $intm_cnf -policy policy_loose -extensions client_cert -notext -md sha256 -in $intm_dir/csr/$name-csr.pem -out $client_dir/certs/$name-cert.pem
  cont $?

  chmod 400 $client_dir/private/$name-key.pem

  convert_certs $client_dir $name
  if [ "$2" == "--pkcs12" ]; then
    export_pkcs12 $client_dir $name
  fi
}

function revoke_client {
  name=$1
  prompt "revoking client certificate for $name"
  openssl ca -config $intm_cnf -revoke $client_dir/certs/$name-cert.pem
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
  prompt "exporting to pkcs12 format"
  openssl pkcs12 -export -out $dir/$name.p12 -inkey $dir/private/$name-key.pem -in $dir/certs/$name-cert.pem -certfile $intm_dir/certs/intermediate-chain.pem
  cont $?
  echo "$dir/$name.p12"
}


function cont {
  if [ $1 -ne 0 ]; then
    prompt "-----------------"
    prompt "An error occurred" red
    prompt "-----------------"
    exit
  fi
}

if [ -z $use_intermediate ]; then
  # sign all request with root-ca
  intm_dir=$ca_dir
  intm_cnf=$ca_cnf
fi

main $*
