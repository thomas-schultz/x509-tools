#!/bin/bash

function create_server {
  auth_dir="${1:-root-ca}"
  auth_name=`echo $auth_dir | awk -F'-' '{print $1}'`
  name=$2
  if [ -z "$name" ]; then
    echo "usage: $0 [options] create server <ca> <name>" && exit 1
  fi
  bits="${bits:-$srv_bits}"
  days="${days:-$srv_days}"

  attribs=( "countryName" "stateOrProvinceName" "localityName" "organizationName" "organizationalUnitName" "emailAddress" "commonName" "altName" )
  export_params "${attribs[@]}"

  mkdir -p $srv_dir/certs $srv_dir/private $srv_dir/chain
  chmod 700 $srv_dir/private
  prompt "creating private key for $name"
  openssl genrsa -out $srv_dir/private/$name-key.pem $bits
  cont $?

  prompt "creating server certificate for '$name'"
  openssl req $batch_mode -config $srv_cnf -key $srv_dir/private/$name-key.pem $passin -new -out $auth_dir/csr/$name-csr.pem
  cont $?

  prompt "setting subjectAltNames of certificate request for $name"
  openssl asn1parse -inform PEM -in $auth_dir/csr/$name-csr.pem > $auth_dir/csr/$name-csr.txt
  echo "$auth_dir/csr/$name-csr.txt"
  tmp_cnf="${name}-tmp.cnf"
  cp $ca_cnf ./$tmp_cnf
  # extract subjectAltNames from csr file and append it to the configuration
  sed -n '/X509v3 Subject Alternative Name/{n;p;}' $auth_dir/csr/$name-csr.txt | awk '{ print "DNS." ++count[$6] " = " substr($7,2) }' >> $tmp_cnf

  prompt "signing server certificate for $name with CA '$auth_dir'"
  export_cnf $auth_name $auth_dir
  openssl ca $batch_mode -config $tmp_cnf $auth_passin -policy policy_moderate -extensions server_cert -days $days -notext -in $auth_dir/csr/$name-csr.pem -out $srv_dir/certs/$name-cert.pem
  cont $?
  rm $tmp_cnf

  chmod 400 $srv_dir/private/$name-key.pem

  cp $auth_dir/certs/chain.pem $srv_dir/chain/$name-chain.pem

  convert_certs $srv_dir $name
  [ -z $pkcs12 ] || export_pkcs12 $srv_dir $name
}

function create_client {
  auth_dir="${1:-root-ca}"
  auth_name=`echo $auth_dir | awk -F'-' '{print $1}'`
  name=$2
  if [ -z "$name" ]; then
    echo "usage: $0 [options] create client <ca> <name>" && exit 1
  fi
  bits="${bits:-$client_bits}"
  days="${days:-$client_days}"

  attribs=( "countryName" "stateOrProvinceName" "localityName" "organizationName" "organizationalUnitName" "emailAddress" "commonName" "altName" )
  export_params "${attribs[@]}"

  mkdir -p $client_dir/certs $client_dir/private $client_dir/chain
  prompt "creating private key for $name"
  openssl genrsa -out $client_dir/private/$name-key.pem $bits
  cont $?

  prompt "creating client certificate for $name"
  openssl req $batch_mode -config $client_cnf -new -key $client_dir/private/$name-key.pem -out $intm_dir/csr/$name-csr.pem
  cont $?

  prompt "signing client certificate for $name"
  export_cnf $auth_name $auth_dir
  openssl ca $batch_mode -config $ca_cnf -policy policy_loose -extensions client_cert -days $days -notext -in $auth_dir/csr/$name-csr.pem -out $client_dir/certs/$name-cert.pem
  cont $?

  chmod 400 $client_dir/private/$name-key.pem

  cp $auth_dir/certs/chain.pem $client_dir/chain/$name-chain.pem

  convert_certs $client_dir $name
  [ -z $pkcs12 ] || export_pkcs12 $srv_dir $name
}

function revoke_server {
  auth_dir="${1:-root-ca}"
  auth_name=`echo $auth_dir | awk -F'-' '{print $1}'`
  name=$2
  if [ -z "$name" ]; then
    echo "usage: $0 [options] revoke server <ca> <name>" && exit 1
  fi

  prompt "revoking server certificate for $name"
  export_cnf $auth_name $auth_dir
  openssl ca $batch_mode -config $ca_cnf $auth_passin -revoke $srv_dir/certs/$name-cert.pem
  cont $?
  update_crl $auth_name
}

function revoke_client {
  auth_dir="${1:-root-ca}"
  auth_name=`echo $auth_dir | awk -F'-' '{print $1}'`
  name=$2
  if [ -z "$name" ]; then
    echo "usage: $0 [options] revoke client <ca> <name>" && exit 1
  fi

  prompt "revoking client certificate for $name"
  export_cnf $auth_name $auth_dir
  openssl ca $batch_mode -config $ca_cnf $auth_passin -revoke $client_dir/certs/$name-cert.pem
  cont $?
  update_crl $auth_name
}

function export_pkcs12 {
  dir=$1
  name=$2

  prompt "exporting to pkcs12 format (pw: '$pkcs12')"
  openssl pkcs12 -export -passout pass:$pkcs12 -inkey $dir/private/$name-key.pem -in $dir/certs/$name-cert.pem -certfile $dir/chain/$name-chain.pem -out $dir/$name.p12
  cont $?
  puts "$dir/$name.p12"
}
