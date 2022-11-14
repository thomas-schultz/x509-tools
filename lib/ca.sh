#!/bin/bash

function define_ca {
    ca_dir="$1" && shift
    issuer="$1" && shift


    if [ -f "$ca_dir/presets.cnf" ]; then
      read_presets "$ca_dir/presets.cnf"
    else
      puts "creating directory $ca_dir"
      mkdir -p "$ca_dir/"
    fi

    prepare_config "$ca_dir" "$issuer"
    load_ca "$ca_dir"

    mkdir -p "$ca_certs" "$ca_crl_dir" "$ca_new_certs_dir" "$ca_ocsp_dir" "$ca_csr_dir" "$ca_private_key_dir"
    chmod 700 "$ca_private_key_dir"
    touch "$ca_database" "$ca_database.attr"
    $rand > "$ca_serial"
    $rand > "$ca_crlnumber"
}

function create_ca {
    ca_dir="$1" && shift

    load_ca "$ca_dir"
    extension="v3_ca"

    prompt "creating CA private key for '$ca_subj'"
    create_private_key "$ca_private_key" $ca_keylength

    prompt "creating CA certificate for '$ca_subj'"
    create_self_signed_ca $ca_days $extension

    protect_private_key "$ca_private_key"

    prompt "converting CA certificate into DER and Text format"
    convert_cert "$ca_certificate"

    unfold_chain "$ca_certificate"

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
    ca="$1" && shift
    extension="$1" && shift

    load_ca "$ca"

    prompt "creating intermediate private key for '$ca_subj'"
    create_private_key "$ca_private_key" $ca_keylength

    prompt "creating intermediate certificate signing request towards '$issuer_subj'"
    create_ca_csr $extension

    protect_private_key "$ca_private_key"

    prompt "signing intermediate certificate with CA '$issuer_subj'"
    sign_ca_csr $extension

    if [ ! -z "$crlUrl" ]; then
        prompt "update revocation list for issuer CA '$ca_subj'"
        update_crl "$ca_dir"
    fi

    restore_ca

    prompt "converting CA certificate into DER and Text format"
    convert_cert "$ca_certificate"

    prompt "creating certificate chain"
    if [ -e "$issuer_ca_dir/chain.pem" ]; then
        cat "$ca_certificate" "$issuer_ca_dir/chain.pem" > "$ca_cert_dir/chain.pem"
    else
        cat "$ca_certificate" "$issuer_certificate" > "$ca_cert_dir/chain.pem"
    fi
    puts "$ca_cert_dir/chain.pem"

    prompt "unfolding certificate chain"
    unfold_chain "$ca_cert_dir/chain.pem"

    if [ ! -z "$crlUrl" ]; then
        prompt "update revocation list for CA '$ca_subj'"
        update_crl "$ca_dir"
    fi
    if [ ! -z "$ocspUrl" ]; then
        create_ocsp "$ca_dir"
    fi
}

function create_ocsp {
    ca="$1" && shift

    load_ca "$ca"

    prompt "creating OCSP private key for '$ca_subj'"
    create_private_key "$ca_ocsp_private_key" $cert_bits

    prompt "creating OCSP certificate for '$ca_subj'"
    create_ocsp_csr

    protect_private_key "$ca_ocsp_private_key"

    prompt "signing OCSP certificate with CA '$ca_subj'"
    sign_ocsp_csr $crl_days

    prompt "converting OCSP certificate into DER and Text format"
    convert_cert "$ca_ocsp_certificate"
}

function update_ocsp {
    ca="$1" && shift

    load_ca "$ca"

    prompt "updating certificate database for '$ca_subj'"
    update_db
}

function revoke_ca {
    ca="$1" && shift

    load_ca "$ca"

    prompt "revoking CA '$ca_subj' from CA '$issuer_subj'"
    revoke_ca_cert

    if [ ! -z "$crlUrl" ]; then
        prompt "update revocation list for CA '$ca_subj'"
        update_crl "$ca_dir"
    fi
}

function info_ca {
    ca="$1" && shift

    use_ca "$ca"

    issuer=`openssl x509 -in $ca_certificate -noout -issuer`
    subject=`openssl x509 -in $ca_certificate -noout -subject`
    notbefore=`openssl x509 -in $ca_certificate -noout -dates | head -n1`
    notafter=`openssl x509 -in $ca_certificate -noout -dates | tail -n1`

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
