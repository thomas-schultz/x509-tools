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

function create_signer_certificate {
    name="$1" && shift
    ca="$1" && shift
    create_user_certificate "$ca" "$name" "signer_cert" $*
}

function create_user_certificate {
    ca_dir="$1" && shift
    name="$1" && shift
    extension="$1" && shift

    prepare_ca "$ca_dir"
    use_ca "$ca_dir"

    mkdir -p "$ca_dir/user_certs/$name/"

    prompt "creating private key for $name'"
    create_private_key "$ca_dir/user_certs/$name" $keylength

    csr_cnf="$ca_dir/user_certs/$name/cert.cnf"
    puts "append subjectAltNames to csr request"
    append_sans "$csr_cnf"

    prompt "creating certificate request for '$name' towards '$ca_subj'"
    create_user_csr "$ca_dir" "$csr_cnf" "$name"

    convert_csr "$ca_dir/csr/$name-csr.pem"

    prompt "extracting subjectAltNames from CSR for $name"
    extract_san_from_csr "$csr_cnf" "$ca_dir/csr/$name-csr.txt"

    prompt "signing server certificate for '$name' with CA '$ca_subj'"
    sign_user_csr "$ca_dir" "$csr_cnf" $cert_days $extension

    protect_private_key "$ca_dir/user_certs/$name/"

    if [ -e "$ca_dir/certs/chain.pem" ]; then
        cp "$ca_dir/certs/chain.pem" "$ca_dir/user_certs/$name/chain.pem"
    else
        cp "$ca_dir/certs/cert.pem" "$ca_dir/user_certs/$name/chain.pem"
    fi
    cp "$ca_dir/certs/ca."*.pem "$ca_dir/user_certs/$name/"

    convert_cert "$ca_dir/user_certs/$name/cert.pem"

    if [ ! -z "$pkcs12" ]; then
        export_pkcs12 "$name" "$ca_dir"
    fi
}


function revoke_user_certificate {
    ca_dir="$1" && shift
    name="$1" && shift

    use_ca "$ca_dir"

    if [ -e "$ca_dir/user_certs/$name/cert.pem" ]; then
        cert="$ca_dir/user_certs/$name/cert.pem"
    elif [ -e "$ca_dir/newcerts/$name.pem" ]; then
        cert="$ca_dir/newcerts/$name.pem"
    elif [ -e "name" ]; then
        cert="name"
    else
        echo "ERROR in revoke_user_certificate(): certificate '$name' not found!" && exit 1
    fi

    prompt "revoking server certificate '$name'"
    revoke_client_cert "$cert"

    # hack to pass passphrase
    passedout="$passin"
    update_crl "$ca_dir"
}

function export_pkcs12 {
    name="$1" && shift
    use_ca "$1" && shift

    prompt "exporting to pkcs12 format"
    puts "openssl pkcs12 -export $pkcs12_passout -inkey $ca_dir/user_certs/$name/key.pem -in $ca_dir/user_certs/$name/cert.pem -certfile $ca_dir/user_certs/$name/chain.pem -out $ca_dir/user_certs/$name.p12"
    eval openssl pkcs12 -export $pkcs12_passout -inkey "$ca_dir/user_certs/$name/key.pem" -in "$ca_dir/user_certs/$name/cert.pem" -certfile "$ca_dir/user_certs/$name/chain.pem" -out "$ca_dir/user_certs/$name.p12" $output_mode
    cont $?

    echo "$pkcs12_passout" | sed 's/-passout pass://g' > "$ca_dir/user_certs/$name/export.pw"
    cont $?
    puts "$ca_dir/user_certs/$name.p12"
}
