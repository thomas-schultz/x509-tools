#!/bin/bash

function create_private_key {
    key="$1" && shift
    keylength="$1" && shift

    [ -n "$passout" ] && key_passout="-aes256 $passout"
    if [ -n "$ecdsa_curve_x509_tools" ]; then
        puts "openssl ecparam -genkey $ecdsa_curve_x509_tools | openssl ec $key_passout -out $key"
        eval openssl ecparam -genkey $ecdsa_curve_x509_tools | openssl ec $key_passout -out $key
    elif [ -n "${ecdsa_curve_genpkey}" ]; then
        puts "openssl genpkey ${ecdsa_curve_genpkey} ${key_passout} -out ${key}"
        eval openssl genpkey ${ecdsa_curve_genpkey} ${key_passout} -out ${key}
    else
        puts "openssl genrsa $key_passout -out $key $keylength"
        eval openssl genrsa $key_passout -out "$key" $keylength $output_mode
    fi
    cont $?
    puts "$key"
}

function protect_private_key {
    key="$1" && shift

    chmod 400 "$key"
}

function create_self_signed_ca {
    days="$1" && shift
    extension="$1" && shift

    puts "openssl req $batch_mode -config $ca_cnf -extensions $extension -key $ca_private_key $passedout -new -x509 -days $days -out $ca_certificate"
    eval openssl req $batch_mode -config "$ca_cnf" -extensions $extension -key "$ca_private_key" $passedout -new -x509 -days $days -out "$ca_certificate" $output_mode
    cont $?
    puts "$ca_certificate"
}

function create_ca_csr {
    extension="$1" && shift

    puts "openssl req $batch_mode -config $ca_cnf -extensions $extension -key $ca_private_key $passedout -new -out $ca_csr_dir/csr.pem"
    eval openssl req $batch_mode -config "$ca_cnf" -extensions $extension -key "$ca_private_key" $passedout -new -out "$ca_csr_dir/csr.pem" $output_mode
    cont $?
    puts "$ca_csr_dir/csr.pem"
    convert_csr "$ca_csr_dir/csr.pem"
}

function sign_ca_csr {
    extension="$1" && shift

    use_ca "$issuer_dir"

    puts "openssl ca $batch_mode -config $issuer_cnf -extensions $extension $passin -days $ca_days -notext -in $ca_csr_dir/csr.pem -out $ca_certificate"
    eval openssl ca $batch_mode -config "$issuer_cnf" -extensions $extension $passin -days $ca_days -notext -in "$ca_csr_dir/csr.pem" -out "$ca_certificate" $output_mode
    cont $?
    puts "$ca_certificate"
}

function create_ocsp_csr {
    ocsp_cnf="$ca_cnf.ocsp"
    sed -E 's/(commonName_default\s+)= (.*)/\1=OCSP_for_\2/g' "$ca_cnf" > "$ocsp_cnf"

    puts "openssl req $batch_mode -config $ocsp_cnf -new -key $ca_ocsp_dir/key.pem $passedout -out $ca_ocsp_dir/csr.pem"
    eval openssl req $batch_mode -config "$ocsp_cnf" -new -key "$ca_ocsp_dir/key.pem" $passedout -out "$ca_ocsp_dir/csr.pem" $output_mode
    cont $?
    puts "$ca_ocsp_dir/csr.pem"
}

function sign_ocsp_csr {
    days="$1" && shift

    extension="v3_ocsp"
    ocsp_cnf="$ca_cnf.ocsp"

    puts "openssl ca $batch_mode -config $ocsp_cnf -extensions $extension $passedout -days $days -notext -in $ca_ocsp_dir/csr.pem -out $ca_ocsp_dir/cert.pem"
    eval openssl ca $batch_mode -config "$ocsp_cnf" -extensions $extension $passedout -days $days -notext -in "$ca_ocsp_dir/csr.pem" -out "$ca_ocsp_dir/cert.pem" $output_mode
    cont $?
    puts "$ca_ocsp_dir/cert.pem"
}

function update_db {
    puts "openssl ca $batch_mode -config $ca_cnf $passin -updatedb"
    eval openssl ca $batch_mode -config $ca_cnf $passin -updatedb
    cont $?
}

function create_user_csr {
    user_cnf="$1" && shift
    name="$1" && shift

    puts "openssl req $batch_mode -config $user_cnf -key $ca_new_certs_dir/$name/key.pem $passin -new -out $ca_dir/csr/$name-csr.pem"
    eval openssl req $batch_mode -config "$user_cnf" -key "$ca_new_certs_dir/$name/key.pem" $passin -new -out "$ca_dir/csr/$name-csr.pem" $output_mode
    cont $?
    puts "$ca_dir/csr/$name-csr.pem"
}

function sign_user_csr {
    issuer_dir="$1" && shift
    user_cnf="$1" && shift
    days="$1" && shift
    extension="$1" && shift

    puts "openssl ca $batch_mode -config $user_cnf -extensions $extension $passin -days $days -notext -in $ca_dir/csr/$name-csr.pem -out $ca_new_certs_dir/$name/cert.pem"
    eval openssl ca $batch_mode -config "$user_cnf" -extensions $extension $passin -days $days -notext -in "$ca_dir/csr/$name-csr.pem" -out "$ca_new_certs_dir/$name/cert.pem" $output_mode
    cont $?
    puts "$ca_new_certs_dir/$name/cert.pem"
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
    ca="$1" && shift

    load_ca "$ca"
    [ -z "$passin" ] && passin="$passedout"
    puts "openssl ca $batch_mode -config $ca_cnf $passin -gencrl -out $ca_dir/crl/crl.pem"
    eval openssl ca $batch_mode -config "$ca_cnf" $passin -gencrl -out "$ca_dir/crl/crl.pem" $output_mode
    cont $?
    puts "$ca_dir/crl/crl.pem"

    convert_crl "$ca_dir/crl/crl.pem"
}

function revoke_ca_cert {
    use_ca "$issuer_dir"

    [ -z "$passin" ] && passin="$passedout"
    puts "openssl ca $batch_mode -config $ca_cnf $passin -revoke $ca_certificate"
    eval openssl ca $batch_mode -config "$ca_cnf" $passin -revoke "$ca_certificate" $output_mode
    cont $?
}

function revoke_client_cert {
    input="$1" && shift

    puts "openssl ca $batch_mode -config $ca_cnf $passin -revoke $input"
    eval openssl ca $batch_mode -config "$ca_cnf" $passin -revoke "$input" $output_mode
    cont $?
}

function run_ocsp_responder {
    folder="$1" && shift
    port="$1" && shift
    db="$folder/index.txt"
    rsigner="$folder/ocsp/cert.pem"
    rkey="$folder/ocsp/key.pem"
    ca_cert="$folder/ca/cert.pem"
    log="$folder/ocsp.log"

    puts "openssl ocsp -index $db -port $port -rsigner $rsigner -rkey $rkey -CA $ca_cert -text -out $log"
    openssl ocsp -index "$db" -port "$port" -rsigner "$rsigner" -rkey "$rkey" -CA "$ca_cert" -text -out "$log" -nrequest 1
}
