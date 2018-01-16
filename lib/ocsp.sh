#!/bin/bash

function create_ocsp {
  # create ocsp certificate
  openssl req $batch_mode -config $ca_cnf -extensions v3_ocsp -new -nodes -keyout $ca_dir/private/ocsp.pem -out $ca_dir/csr/ocsp.csr
  openssl ca $batch_mode -config $ca_cnf -extensions v3_ocsp $auth_passin -in $ca_dir/csr/ocsp.csr -out $ca_dir/csr/ocsp.pem
}
