#!/bin/bash

function create_ca {
  name="${1:-root}"
  type="root-ca"
  ca_dir="$name-ca"
  bits="${bits:-$ca_bits}"
  days="${days:-$ca_days}"
  policy="policy_strict"
  extensions="v3_ca"

  [ -z $crlUrl ] || extensions="${extensions}_crl"
  export_params
  export_ca_dir $ca_dir

  # create root-ca folders
  mkdir -p $ca_dir/
  mkdir -p $ca_dir/certs $ca_dir/crl $ca_dir/newcerts $ca_dir/csr $ca_dir/private
  chmod 700 $ca_dir/private
  touch $ca_dir/index.txt
  # workaround for "Can't open $ca_dir/index.txt.attr for reading, No such file or directory"
  touch $ca_dir/index.txt.attr
  $rand > $ca_dir/serial
  $rand > $ca_dir/crlnumber
  echo $type > $ca_dir/type

  # create root-CA private key:
  prompt "creating root private key"
  openssl genrsa -aes256 $passout -out $ca_dir/private/key.pem $bits
  cont $?

  # create root certificate
  prompt "creating root certificate"
  openssl req $batch_mode -config $ca_cnf -extensions $extensions -key $ca_dir/private/key.pem $passin -new -x509 -days $days -out $ca_dir/certs/cert.pem
  cont $?

  chmod 400 $ca_dir/private/key.pem

  prompt "exporting root certificate"
  openssl x509 -outform der -in $ca_dir/certs/cert.pem -out $ca_dir/certs/cert.crt
  puts "$ca_dir/certs/cert.crt"
  openssl x509 -noout -text -in $ca_dir/certs/cert.pem > $ca_dir/certs/cert.txt
  puts "$ca_dir/certs/cert.txt"
  chmod 444 $ca_dir/certs/cert.*

  prompt "link certificate as chain"
  cd $ca_dir/certs && ln -s cert.pem chain.pem && cd - >/dev/null
  puts "$ca_dir/certs/chain.pem"
  cd $ca_dir/certs && ln -s cert.crt chain.crt && cd - >/dev/null
  puts "$ca_dir/certs/chain.crt"

  update_crl $name
}

function create_intermediate {
  auth_dir="${1:-root-ca}"
  auth_name=`echo $auth_dir | awk -F'-' '{print $1}'`
  auth_type=`cat $auth_dir/type`
  name="${2:-intermediate}"
  type="intermediate-ca"
  intm_dir="$name-ca"
  bits="${bits:-$intm_bits}"
  days="${days:-$intm_days}"
  policy="policy_loose"
  extensions="v3_intermediate_ca"

  [ -z $crlUrl ] || extensions="${extensions}_crl"
  export_params
  export_ca_dir $intm_dir

  # create intermediate folder
  mkdir -p $intm_dir
  mkdir -p $intm_dir/certs $intm_dir/crl $intm_dir/newcerts $intm_dir/csr $intm_dir/private
  chmod 700 $intm_dir/private
  touch $intm_dir/index.txt
  # workaround for "Can't open $intm_dir/index.txt.attr for reading, No such file or directory"
  touch $intm_dir/index.txt.attr
  $rand > $intm_dir/serial
  $rand > $intm_dir/crlnumber
  echo $type > $intm_dir/type

  # create intermediate private key
  prompt "creating intermediate private key"
  openssl genrsa -aes256 $passout -out $intm_dir/private/key.pem $bits
  cont $?

  # create and sign intermediate certificate
  prompt "creating intermediate certificate"
  openssl req $batch_mode -config $ca_cnf -key $intm_dir/private/key.pem $passin -new -out $intm_dir/csr/csr.pem
  cont $?


  prompt "signing intermediate certificate with CA '$auth_dir'"
  export_ca_dir $auth_dir
  openssl ca $batch_mode -config $ca_cnf -extensions $extensions $auth_passin -days $days -notext -in $intm_dir/csr/csr.pem -out $intm_dir/certs/cert.pem
  cont $?

  chmod 400 $intm_dir/private/key.pem

  prompt "exporting intermediate certificate"
  openssl x509 -noout -text -in $intm_dir/certs/cert.pem > $intm_dir/certs/cert.txt
  puts "$intm_dir/certs/cert.txt"
  chmod 444 $intm_dir/certs/cert.*

  update_crl $name

  prompt "creating certificate chain"
  cat $auth_dir/certs/chain.pem $intm_dir/certs/cert.pem > $intm_dir/certs/chain.pem
  puts "$intm_dir/certs/chain.pem"
  openssl x509 -outform der -in $intm_dir/certs/chain.pem -out $intm_dir/certs/chain.crt
  puts "$intm_dir/certs/chain.crt"
}

function update_crl {
  ca_name="${1:-root}"
  ca_dir="$name-ca"
  ca_type=`cat $ca_dir/type`

  prompt "updating revocation list of CA '$ca_dir'"
  export_ca_dir $ca_dir
  openssl ca $batch_mode -config $ca_cnf $auth_passin -gencrl -out $ca_dir/crl/crl.pem
  cont $?
  puts "$ca_dir/crl/crl.pem"
  openssl crl -in $ca_dir/crl/crl.pem -noout -text > $ca_dir/crl/crl.txt
  puts "$ca_dir/crl/crl.pem"
}

function revoke_ca {
  ca_dir="${1:-root-ca}"
  ca_name=`echo $ca_dir | awk -F'-' '{print $1}'`
  revoke_dir="${2:-intermediate-ca}"
  revoke_name=`echo $revoke_dir | awk -F'-' '{print $1}'`

  prompt "revoking intermediate '$revoke_dir' of CA '$ca_dir'"
  export_ca_dir $ca_dir
  export_nil
  openssl ca $batch_mode -config $ca_cnf $auth_passin -revoke $revoke_dir/certs/cert.pem
  cont $?
  update_crl $ca_name
}
