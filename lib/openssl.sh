#!/bin/bash

function create_private_key {
    dir="$1" && shift
    keylength="$1" && shift

    [ -z "$passout" ] || key_passout="-aes256 $passout"
    if [ -z "$ecdsa_curve_x509_tools" ]
    then
        puts "openssl genrsa $key_passout -out $dir/key.pem $keylength"
        eval openssl genrsa $key_passout -out "$dir/key.pem" $keylength $output_mode
    else
        puts "openssl ecparam -genkey $ecdsa_curve_x509_tools | openssl ec $key_passout -out $dir/key.pem"
        eval openssl ecparam -genkey $ecdsa_curve_x509_tools | openssl ec $key_passout -out $dir/key.pem
    fi
    cont $?
    puts "$dir/key.pem"
}

function protect_private_key {
    dir="$1" && shift

    chmod 400 "$dir/key.pem"
}

function create_self_signed_ca {
    ca_dir="$1" && shift
    ca_cnf="$1" && shift
    days="$1" && shift
    extension="$1" && shift

    puts "openssl req $batch_mode -config $ca_cnf -extensions $extension -key $ca_dir/private/key.pem $passedout -new -x509 -days $days -out $ca_dir/certs/cert.pem"
    eval openssl req $batch_mode -config "$ca_cnf" -extensions $extension -key "$ca_dir/private/key.pem" $passedout -new -x509 -days $days -out "$ca_dir/certs/cert.pem" $output_mode
    cont $?
    puts "$ca_dir/certs/cert.pem"
}

function create_ca_csr {
    ca_dir="$1" && shift
    ca_cnf="$1" && shift
    extension="$1" && shift

    puts "openssl req $batch_mode -config $ca_cnf -extensions $extension -key $ca_dir/private/key.pem $passedout -new -out $ca_dir/csr/csr.pem"
    eval openssl req $batch_mode -config "$ca_cnf" -extensions $extension -key "$ca_dir/private/key.pem" $passedout -new -out "$ca_dir/csr/csr.pem" $output_mode
    cont $?
    puts "$ca_dir/csr/csr.pem"
    convert_csr "$ca_dir/csr/csr.pem"
}

function sign_ca_csr {
    ca_dir="$1" && shift
    extension="$1" && shift

    prepare_issuer "$issuer_dir"

    puts "openssl ca $batch_mode -config $issuer_cnf -extensions $extension $passin -days $ca_days -notext -in $sub_dir/csr/csr.pem -out $sub_dir/certs/cert.pem"
    eval openssl ca $batch_mode -config "$issuer_cnf" -extensions $extension $passin -days $ca_days -notext -in "$sub_dir/csr/csr.pem" -out "$sub_dir/certs/cert.pem" $output_mode
    cont $?
    puts "$sub_dir/certs/cert.pem"
}

function create_ocsp_csr {
    ca_dir="$1" && shift
    ca_cnf="$1" && shift

    ocsp_cnf="$ca_cnf.ocsp"
    sed -E 's/(commonName_default\s+)= (.*)/\1=OCSP_for_\2/g' "$ca_cnf" > "$ocsp_cnf"

    puts "openssl req $batch_mode -config $ocsp_cnf -new -key $ca_dir/ocsp/key.pem $passedout -out $ca_dir/csr/ocsp.pem"
    eval openssl req $batch_mode -config "$ocsp_cnf" -new -key "$ca_dir/ocsp/key.pem" $passedout -out "$ca_dir/csr/ocsp.pem" $output_mode
    cont $?
    puts "$ca_dir/csr/csr.pem"
}

function sign_ocsp_csr {
    issuer_dir="$1" && shift
    days="$1" && shift

    extension="v3_ocsp"
    ocsp_cnf="$ca_cnf.ocsp"

    puts "openssl ca $batch_mode -config $ocsp_cnf -extensions $extension $passedout -days $days -notext -in $ca_dir/csr/ocsp.pem -out $ca_dir/ocsp/cert.pem"
    eval openssl ca $batch_mode -config "$ocsp_cnf" -extensions $extension $passedout -days $days -notext -in "$ca_dir/csr/ocsp.pem" -out "$ca_dir/ocsp/cert.pem" $output_mode
    cont $?
    puts "$ca_dir/ocsp/cert.pem"
}

function create_user_csr {
    ca_dir="$1" && shift
    ca_cnf="$1" && shift
    name="$1" && shift

    puts "openssl req $batch_mode -config $ca_cnf -key $ca_dir/user_certs/$name/key.pem $passin -new -out $ca_dir/csr/$name-csr.pem"
    eval openssl req $batch_mode -config "$ca_cnf" -key "$ca_dir/user_certs/$name/key.pem" $passin -new -out "$ca_dir/csr/$name-csr.pem" $output_mode
    cont $?
    puts "$ca_dir/csr/$name-csr.pem"
}

function sign_user_csr {
    issuer_dir="$1" && shift
    user_cnf="$1" && shift
    days="$1" && shift
    extension="$1" && shift

    puts "openssl ca $batch_mode -config $user_cnf -extensions $extension $passin -days $days -notext -in $ca_dir/csr/$name-csr.pem -out $ca_dir/user_certs/$name/cert.pem"
    eval openssl ca $batch_mode -config "$user_cnf" -extensions $extension $passin -days $days -notext -in "$ca_dir/csr/$name-csr.pem" -out "$ca_dir/user_certs/$name/cert.pem" $output_mode
    cont $?
    puts "$ca_dir/user_certs/$name/cert.pem"
}

function convert_cert {
    input="$1" && shift
    basename=`basename $input`
    dirname=`dirname $input`
    filename="${basename%.*}"

    eval openssl x509 -outform der -in "$input" -out "$dirname/$filename.der" $output_mode
    puts "$dirname/$filename.der"
    eval openssl x509 -noout -text -in "$input" > "$dirname/$filename.txt"
    puts "$dirname/$filename.txt"
}

function convert_csr {
    input="$1" && shift
    basename=`basename $input`
    dirname=`dirname $input`
    filename="${basename%.*}"

    eval openssl req -outform der -in "$input" -out "$dirname/$filename.der" $output_mode
    puts "$dirname/$filename.der"
    eval openssl req -in "$input" -noout -text > "$dirname/$filename.txt"
    puts "$dirname/$filename.txt"
}

function convert_crl {
    input="$1" && shift
    basename=`basename $input`
    dirname=`dirname $input`
    filename="${basename%.*}"

    eval openssl crl -in "$input" -outform der -out "$dirname/$filename.der" $output_mode
    puts "$dirname/$filename.der"
    eval openssl crl -in "$input" -noout -text > "$dirname/$filename.txt"
    puts "$dirname/$filename.txt"
}

function unfold_chain {
    input="$1" && shift
    basename=`basename $input`
    dirname=`dirname $input`

    cat "$input" | \
        awk 'split_after==1{n++;split_after=0} /-----END CERTIFICATE-----/ {split_after=1} \
        {print > "'$dirname'/ca." n+1 ".pem"}'
    count=`grep -c "END CERTIFICATE" $input`
    for i in `seq 1 $count`; do
        puts "$dirname/ca.$i.pem"
    done
}

function update_crl {
    ca_dir="$1" && shift
    ca_cnf="$1" && shift

    prepare_ca "$ca_dir"

    [ -z "$passin" ] && passin="$passedout"
    puts "openssl ca $batch_mode -config $ca_cnf $passin -gencrl -out $ca_dir/crl/crl.pem"
    eval openssl ca $batch_mode -config "$ca_cnf" $passin -gencrl -out "$ca_dir/crl/crl.pem" $output_mode
    cont $?
    puts "$ca_dir/crl/crl.pem"

    convert_crl "$ca_dir/crl/crl.pem"
}

function revoke_ca_cert {
    ca_dir="$1" && shift

    prepare_issuer "$issuer_dir"

    [ -z "$passin" ] && passin="$passedout"
    puts "openssl ca $batch_mode -config $ca_cnf $passin -revoke $sub_dir/certs/cert.pem"
    eval openssl ca $batch_mode -config "$ca_cnf" $passin -revoke "$sub_dir/certs/cert.pem" $output_mode
    cont $?
}

function revoke_client_cert {
    input="$1" && shift

    puts "openssl ca $batch_mode -config $ca_cnf $passin -revoke $input"
    eval openssl ca $batch_mode -config "$ca_cnf" $passin -revoke "$input" $output_mode
    cont $?
}

function run_ocsp_responder {
    #openssl ocsp -index root-ca/index.txt -port 8888 -rsigner root-ca/certs/ocsp.pem -rkey root-ca/private/ocsp-key.pem -CA root-ca/certs/cert.pem -text -out log.txt
    #openssl ocsp -CAfile root-ca/certs/cert.pem -issuer root-ca/certs/cert.pem -cert root-ca/newcerts/1541EBB0B1586558.pem -url http://localhost:8888 -resp_text
    echo "not yet implemented"
}
