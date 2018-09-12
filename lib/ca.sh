#!/bin/bash

function define_ca {
    ca_dir="$1" && shift
    issuer="$1" && shift

    [ -f "$ca_dir/presets.cnf" ] && read_presets "$ca_dir/presets.cnf"

    puts "creating directory $ca_dir"
    mkdir -p "$ca_dir/"
    mkdir -p "$ca_dir/certs" "$ca_dir/crl" "$ca_dir/ocsp" "$ca_dir/newcerts" "$ca_dir/csr" "$ca_dir/private"
    chmod 700 "$ca_dir/private"
    touch "$ca_dir/index.txt"
    touch "$ca_dir/index.txt.attr"
    $rand > "$ca_dir/serial"
    $rand > "$ca_dir/crlnumber"
    prepare_config "$ca_dir" "$issuer"
}

function create_ca {
    ca_dir="$1" && shift
    prepare_ca "$ca_dir"
    extension="v3_ca"

    prompt "creating CA private key for '$ca_subj'"
    create_private_key "$ca_dir/private" $ca_keylength

    prompt "creating CA certificate for '$ca_subj'"
    create_self_signed_ca "$ca_dir" "$ca_cnf" $ca_days $extension

    protect_private_key "$ca_dir/private"

    prompt "converting CA certificate into DER and Text format"
    convert_cert "$ca_dir/certs/cert.pem"

    unfold_chain "$ca_dir/certs/cert.pem"

    if [ ! -z "$crlUrl" ]; then
        prompt "creating revocation list for CA '$ca_subj'"
        update_crl "$ca_dir"
    fi
    if [ ! -z "$ocspUrl" ]; then
        create_ocsp "$ca_dir"
    fi
}

function create_sub_ca {
    issuer="$1" && shift
    create_intermediate_ca "$issuer" "v3_sub_ca" $*
}


function create_end_ca {
    issuer="$1" && shift
    create_intermediate_ca "$issuer" "v3_end_ca" $*
}

function create_intermediate_ca {
    ca_dir="$1" && shift
    extension="$1" && shift

    prepare_ca "$ca_dir"

    prompt "creating intermediate private key for '$ca_subj'"
    create_private_key "$ca_dir/private" $ca_keylength

    prompt "creating intermediate certificate signing request towards '$issuer_subj'"
    create_ca_csr "$ca_dir" "$ca_cnf" $extension

    protect_private_key "$ca_dir/private"

    prompt "signing intermediate certificate with CA '$issuer_subj'"
    sign_ca_csr "$ca_dir" $extension

    if [ ! -z "$crlUrl" ]; then
        prompt "update revocation list for issuer CA '$ca_subj'"
        update_crl "$ca_dir"
    fi

    restore_ca

    prompt "converting CA certificate into DER and Text format"
    convert_cert "$ca_dir/certs/cert.pem"

    prompt "creating certificate chain"
    if [ -e "$issuer_dir/certs/chain.pem" ]; then
        cat "$ca_dir/certs/cert.pem" "$issuer_dir/certs/chain.pem" > "$ca_dir/certs/chain.pem"
    else
        cat "$ca_dir/certs/cert.pem" "$issuer_dir/certs/cert.pem" > "$ca_dir/certs/chain.pem"
    fi
    puts "$ca_dir/certs/chain.pem"

    prompt "unfolding certificate chain"
    unfold_chain "$ca_dir/certs/chain.pem"

    if [ ! -z "$crlUrl" ]; then
        prompt "update revocation list for CA '$ca_subj'"
        update_crl "$ca_dir"
    fi
    if [ ! -z "$ocspUrl" ]; then
        create_ocsp "$ca_dir"
    fi
}

function create_ocsp {
    ca_dir="$1" && shift

    prepare_ca "$ca_dir" && shift

    prompt "creating OCSP private key for '$ca_subj'"
    create_private_key "$ca_dir/ocsp" $cert_bits

    prompt "creating OCSP certificate for '$ca_subj'"
    create_ocsp_csr "$ca_dir" "$ca_cnf"

    protect_private_key "$ca_dir/ocsp/"

    prompt "signing OCSP certificate with CA '$ca_subj'"
    sign_ocsp_csr "$ca_dir" $crl_days

    prompt "converting OCSP certificate into DER and Text format"
    convert_cert "$ca_dir/ocsp/cert.pem"
}

function revoke_ca {
    ca_dir="$1" && shift

    prepare_ca "$ca_dir"

    prompt "revoking CA '$ca_subj' from CA '$issuer_subj'"
    revoke_ca_cert "$ca_dir"

    if [ ! -z "$crlUrl" ]; then
        prompt "update revocation list for CA '$ca_subj'"
        update_crl "$ca_dir"
    fi
}

function info_ca {
    ca_dir="$1" && shift

    use_ca "$ca_dir"

    issuer=`openssl x509 -in $ca_dir/certs/cert.pem -noout -issuer`
    subject=`openssl x509 -in $ca_dir/certs/cert.pem -noout -subject`
    notbefore=`openssl x509 -in $ca_dir/certs/cert.pem -noout -dates | head -n1`
    notafter=`openssl x509 -in $ca_dir/certs/cert.pem -noout -dates | tail -n1`

    echo "###############################"
    echo "CA: $ca_dir"
    echo "###############################"
    printf "  %s\n" "$subject"
    printf "  %s\n" "$issuer"
    printf "  %s\n" "$notbefore"
    printf "  %s\n" "$notafter"
    echo "issued certificates:"
    echo "-------------------------------"
    cat "$ca_dir/index.txt"
    echo "-------------------------------"
    echo ""
}
