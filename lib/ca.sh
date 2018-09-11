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

    # create root-CA private key:
    prompt "creating CA private key"
    [ -z "$passout" ] || key_passout="-aes256 $passout"
    puts "openssl genrsa $key_passout -out $ca_dir/private/key.pem $ca_keylength"
    openssl genrsa $key_passout -out "$ca_dir/private/key.pem" $ca_keylength
    cont $?

    # create root certificate
    prompt "creating CA certificate"
    puts "openssl req $batch_mode -config $ca_cnf -extensions $extension -key $ca_dir/private/key.pem $passedout -new -x509 -days $ca_days -out $ca_dir/certs/cert.pem"
    openssl req $batch_mode -config "$ca_cnf" -extensions $extension -key "$ca_dir/private/key.pem" $passedout -new -x509 -days $ca_days -out "$ca_dir/certs/cert.pem"
    cont $?

    chmod 400 "$ca_dir/private/key.pem"

    prompt "converting CA certificate files to DER and Text form"
    openssl x509 -outform der -in "$ca_dir/certs/cert.pem" -out "$ca_dir/certs/cert.der"
    puts "$ca_dir/certs/cert.der"
    openssl x509 -noout -text -in "$ca_dir/certs/cert.pem" > "$ca_dir/certs/cert.txt"
    puts "$ca_dir/certs/cert.txt"
    cp "$ca_dir/certs/cert.pem" "$ca_dir/certs/ca.1.pem"
    chmod 444 "$ca_dir/certs/cert".*

    if [ ! -z "$crlUrl" ]; then
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
    prepare_ca "$1" && shift
    extension="$1" && shift

    # create intermediate private key
    prompt "creating intermediate private key"
    [ -z "$passout" ] || key_passout="-aes256 $passout"
    puts "openssl genrsa $key_passout -out $ca_dir/private/key.pem $ca_keylength"
    openssl genrsa $key_passout -out "$ca_dir/private/key.pem" $ca_keylength
    cont $?

    # create and sign intermediate certificate
    prompt "creating intermediate certificate"
    puts "openssl req $batch_mode -config $ca_cnf -extensions $extension -key $ca_dir/private/key.pem $passedout -new -out $ca_dir/csr/csr.pem"
    openssl req $batch_mode -config "$ca_cnf" -extensions $extension -key "$ca_dir/private/key.pem" $passedout -new -out "$ca_dir/csr/csr.pem"
    cont $?

    chmod 400 "$ca_dir/private/key.pem"

    prompt "signing intermediate certificate with CA '$issuer'"
    prepare_issuer "$issuer"
    puts "openssl ca $batch_mode -config $issuer_cnf -extensions $extension $passin -days $ca_days -notext -in $sub_dir/csr/csr.pem -out $sub_dir/certs/cert.pem"
    openssl ca $batch_mode -config "$issuer_cnf" -extensions $extension $passin -days $ca_days -notext -in "$sub_dir/csr/csr.pem" -out "$sub_dir/certs/cert.pem"
    cont $?

    # update crl of issuer
    if [ ! -z "$crlUrl" ]; then
        update_crl "$issuer"
    fi

    ca_dir="$sub_dir" # restores ca_dir to current
    if [ ! -z "$crlUrl" ]; then
        update_crl "$ca_dir"
    fi
    if [ ! -z "$ocspUrl" ]; then
        create_ocsp "$ca_dir"
    fi

    prompt "converting CA certificate files to DER and Text form"
    openssl x509 -outform der -in "$ca_dir/certs/cert.pem" -out "$ca_dir/certs/cert.der"
    puts "$ca_dir/certs/cert.der"
    openssl x509 -noout -text -in "$ca_dir/certs/cert.pem" > "$ca_dir/certs/cert.txt"
    puts "$ca_dir/certs/cert.txt"
    chmod 444 "$ca_dir/certs/cert".*

    prompt "creating certificate chain"
    if [ -e "$issuer_dir/certs/chain.pem" ]; then
        cat "$ca_dir/certs/cert.pem" "$issuer_dir/certs/chain.pem" > "$ca_dir/certs/chain.pem"
    else
        cat "$ca_dir/certs/cert.pem" "$issuer_dir/certs/cert.pem" > "$ca_dir/certs/chain.pem"
    fi
    puts "$ca_dir/certs/chain.pem"
    cat "$ca_dir/certs/chain.pem" | \
        awk 'split_after==1{n++;split_after=0} /-----END CERTIFICATE-----/ {split_after=1} \
        {print > "'$ca_dir'/certs/ca." n+1 ".pem"}'
    count=`grep -c "END CERTIFICATE" $ca_dir/certs/chain.pem`
    puts "$ca_dir/certs/ca.[1-$count].pem"
    openssl x509 -outform der -in "$ca_dir/certs/chain.pem" -out "$ca_dir/certs/chain.der"
    puts "$ca_dir/certs/chain.der"
}

function create_ocsp {
    prepare_ca "$1" && shift

    prompt "creating OCSP private key for '$ca_dir'"
    openssl genrsa -out "$ca_dir/ocsp/key.pem" $cert_bits
    cont $?

    prompt "creating OCSP certificate for '$ca_dir'"
    tmp_cnf="$ca_cnf.ocsp"
    sed -E 's/(commonName_default\s+)= (.*)/\1=OCSP_for_\2/g' "$ca_cnf" > "$tmp_cnf"
    puts "openssl req $batch_mode -config $tmp_cnf -new -key $ca_dir/ocsp/key.pem $passedout -out $ca_dir/csr/ocsp.pem"
    openssl req $batch_mode -config "$tmp_cnf" -new -key "$ca_dir/ocsp/key.pem" $passedout -out "$ca_dir/csr/ocsp.pem"
    cont $?

    rm "$tmp_cnf"
    chmod 400 "$ca_dir/ocsp/key.pem"

    prompt "signing OCSP certificate with CA '$ca_dir'"

    sed -E 's/(policy\s+)= (.*)/\1= policy_ocsp/g' "$ca_cnf" > "$tmp_cnf"
    puts "openssl ca $batch_mode -config $tmp_cnf -extensions "v3_ocsp" $passedout -days $crl_days -notext -in $ca_dir/csr/ocsp.pem -out $ca_dir/ocsp/cert.pem"
    openssl ca $batch_mode -config "$tmp_cnf" -extensions "v3_ocsp" $passedout -days $crl_days -notext -in "$ca_dir/csr/ocsp.pem" -out "$ca_dir/ocsp/ocsp.pem"
    cont $?

    prompt "converting OCSP certificate files to DER and Text form"
    openssl x509 -outform der -in "$ca_dir/ocsp/cert.pem" -out "$ca_dir/ocsp/cert.der"
    puts "$ca_dir/ocsp/cert.der"
    openssl x509 -noout -text -in "$ca_dir/ocsp/cert.pem" > "$ca_dir/ocsp/cert.txt"
    puts "$ca_dir/ocsp/cert.txt"
    chmod 444 "$ca_dir/ocsp/cert".*

    #openssl ocsp -index root-ca/index.txt -port 8888 -rsigner root-ca/certs/ocsp.pem -rkey root-ca/private/ocsp-key.pem -CA root-ca/certs/cert.pem -text -out log.txt
    #openssl ocsp -CAfile root-ca/certs/cert.pem -issuer root-ca/certs/cert.pem -cert root-ca/newcerts/1541EBB0B1586558.pem -url http://localhost:8888 -resp_text
}

function update_crl {
    prepare_ca "$1" && shift

    prompt "updating revocation list of CA '$ca_dir'"
    [ -z "$passin" ] && passin="$passedout"
    puts "openssl ca $batch_mode -config $ca_cnf $passin -gencrl -out $ca_dir/crl/crl.pem"
    openssl ca $batch_mode -config "$ca_cnf" $passin -gencrl -out "$ca_dir/crl/crl.pem"
    cont $?

    puts "$ca_dir/crl/crl.pem"
    openssl crl -in "$ca_dir/crl/crl.pem" -outform der -out "$ca_dir/crl/crl.der"
    puts "$ca_dir/crl/crl.der"
    openssl crl -in "$ca_dir/crl/crl.pem" -noout -text > "$ca_dir/crl/crl.txt"
    puts "$ca_dir/crl/crl.txt"
}

function revoke_ca {
    prepare_ca "$1"
    prepare_issuer "$issuer"

    prompt "revoking CA '$sub_dir' from CA '$ca_dir'"
    [ -z "$passin" ] && passin="$passedout"
    puts "openssl ca $batch_mode -config $issuer_cnf $passin -revoke $sub_dir/certs/cert.pem"
    openssl ca $batch_mode -config "$issuer_cnf" $passin -revoke "$sub_dir/certs/cert.pem"
    cont $?

    update_crl "$ca_dir"
}

function info_ca {
    use_ca $1

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
