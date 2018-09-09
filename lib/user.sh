#!/bin/bash


function create_server_certificate {
    name="$1" && shift
    ca="$1" && shift
    create_user_certificate "$ca" "$name" "server_cert" $*
}

function create_client_certificate {
    name="$1" && shift
    ca="$1" && shift
    create_user_certificate "$ca" "$name" "client_cert" $*
}

function create_user_certificate {
    prepare_ca "$1" && shift
    name="$1" && shift
    extension="$1" && shift

    mkdir -p "$ca_dir/user_certs/$name/"

    prompt "creating private key for $name"
    openssl genrsa -out "$ca_dir/user_certs/$name/key.pem" $keylength
    cont $?

    tmp_cnf="$ca_dir/user_certs/$name/cert.cnf"
    puts "append subjectAltNames to config file $tmp_cnf"
    append_sans "$tmp_cnf"

    prompt "creating certificate request for '$name'"
    puts "openssl req $batch_mode -config $tmp_cnf -key $ca_dir/user_certs/$name/key.pem $passin -new -out $ca_dir/csr/$name-csr.pem"
    openssl req $batch_mode -config "$tmp_cnf" -key "$ca_dir/user_certs/$name/key.pem" $passin -new -out "$ca_dir/csr/$name-csr.pem"
    cont $?

    openssl req -in "$ca_dir/csr/$name-csr.pem" -text -noout > "$ca_dir/csr/$name-csr.txt"
    puts "$ca_dir/csr/$name-csr.txt"
    rm "$tmp_cnf"

    prompt "extracting subjectAltNames from CSR for $name"
    extract_san_from_csr "$tmp_cnf" "$ca_dir/csr/$name-csr.txt"

    prompt "signing server certificate for $name with CA '$ca_dir'"
    puts "openssl ca $batch_mode -config $tmp_cnf -extensions $extension $passin -days $cert_days -notext -in $ca_dir/csr/$name-csr.pem -out $ca_dir/user_certs/$name/cert.pem"
    openssl ca $batch_mode -config "$tmp_cnf" -extensions $extension $passin -days $cert_days -notext -in "$ca_dir/csr/$name-csr.pem" -out "$ca_dir/user_certs/$name/cert.pem"
    cont $?

    openssl x509 -noout -text -in "$ca_dir/user_certs/$name/cert.pem" > "$ca_dir/user_certs/$name/cert.txt"
    puts "$ca_dir/user_certs/$name/cert.txt"

    chmod 400 "$ca_dir/user_certs/$name/key.pem"
    rm "$tmp_cnf"

    if [ -e "$ca_dir/certs/chain.pem" ]; then
        cp "$ca_dir/certs/chain.pem" "$ca_dir/user_certs/$name/chain.pem"
    else
        cp "$ca_dir/certs/cert.pem" "$ca_dir/user_certs/$name/chain.pem"
    fi
    cp "$ca_dir/certs/ca."*.pem "$ca_dir/user_certs/$name/"
    
    convert_certs "$ca_dir/user_certs/$name"
    if [ ! -z "$pkcs12" ]; then
		export_pkcs12 "$ca_dir" "$name"
	fi
}


function revoke_user_certificate {
    use_ca "$1" && shift
    name="$1" && shift

    puts "$ca_dir/user_certs/$name/cert.pem"

    prompt "revoking server certificate for $name"
    if [ -e "$ca_dir/user_certs/$name/cert.pem" ]; then
        cert="$ca_dir/user_certs/$name/cert.pem"
    elif [ -e "$ca_dir/newcerts/$name.pem" ]; then
        cert="$ca_dir/newcerts/$name.pem"
    else
        echo "ERROR in revoke_user_certificate(): certificate '$name' not found!"
        exit 1
    fi
    echo $cert
    puts "openssl ca $batch_mode -config $ca_cnf $passin -revoke $cert"
    openssl ca $batch_mode -config "$ca_cnf" $passin -revoke "$cert"
    cont $?

    passedout="$passin" # hack to pass passphrase
    update_crl "$ca_dir"
}

function export_pkcs12 {
    use_ca "$1" && shift
    name="$1" && shift

    prompt "exporting to pkcs12 format"
    puts "openssl pkcs12 -export $pkcs12_passout -inkey $ca_dir/user_certs/$name/key.pem -in $ca_dir/user_certs/$name/cert.pem -certfile $ca_dir/user_certs/$name/chain.pem -out $ca_dir/user_certs/$name.p12"
    openssl pkcs12 -export $pkcs12_passout -inkey "$ca_dir/user_certs/$name/key.pem" -in "$ca_dir/user_certs/$name/cert.pem" -certfile "$ca_dir/user_certs/$name/chain.pem" -out "$ca_dir/user_certs/$name.p12"
    cont $?

    echo "$pkcs12_passout" | sed 's/-passout pass://g' > "$ca_dir/user_certs/$name/export.pw"
    cont $?
    puts "$ca_dir/user_certs/$name.p12"
}
