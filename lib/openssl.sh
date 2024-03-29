#!/bin/bash

function create_private_key {
    key="$1" && shift
    keylength="$1" && shift

    [ -n "${passout[*]}" ] && key_passout=(-aes256 "${passout[@]}")
    if [ -n "${ecdsa_curve_x509_tools[*]}" ]; then
        puts "openssl ecparam -genkey ${ecdsa_curve_x509_tools[*]} | <openssl_command>"
        openssl ecparam -genkey "${ecdsa_curve_x509_tools[@]}" | openssl_func ec "${key_passout[@]}" -out "$key"
    elif [ -n "${ecdsa_curve_genpkey[*]}" ]; then
        openssl_func genpkey "${ecdsa_curve_genpkey[@]}" "${key_passout[@]}" -out "${key}"
    else
        openssl_func genrsa "${key_passout[@]}" -out "$key" $keylength
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

    openssl_func req "$batch_mode" -config "$ca_cnf" -extensions "$extension" -key "$ca_private_key" "${passedout[@]}" -new -x509 -days "$days" -out "$ca_certificate"
    cont $?
    puts "$ca_certificate"
}

function create_ca_csr {
    extension="$1" && shift

    openssl_func req "$batch_mode" -config "$ca_cnf" -extensions "$extension" -key "$ca_private_key" "${passedout[@]}" -new -out "$ca_csr_dir/csr.pem"
    cont $?
    puts "$ca_csr_dir/csr.pem"
    convert_csr "$ca_csr_dir/csr.pem"
}

function sign_ca_csr {
    extension="$1" && shift
    modify="$( date_modify )"

    use_ca "$issuer_dir"

    openssl_func ca "$batch_mode" $modify -config "$issuer_cnf" -extensions "$extension" "${passin[@]}" -days "$ca_days" -notext -in "$ca_csr_dir/csr.pem" -out "$ca_certificate"
    cont $?
    puts "$ca_certificate"
}

function create_ocsp_csr {
    ocsp_cnf="$ca_cnf.ocsp"
    sed -E 's/(commonName_default\s+)= (.*)/\1=OCSP_for_\2/g' "$ca_cnf" > "$ocsp_cnf"

    openssl_func req "$batch_mode" -config "$ocsp_cnf" -new -key "$ca_ocsp_dir/key.pem" "${passedout[@]}" -out "$ca_ocsp_dir/csr.pem"
    cont $?
    puts "$ca_ocsp_dir/csr.pem"
}

function sign_ocsp_csr {
    days="$1" && shift

    extension="v3_ocsp"
    ocsp_cnf="$ca_cnf.ocsp"

    openssl_func ca "$batch_mode" -config "$ocsp_cnf" -extensions "$extension" "${passedout[@]}" -days "$days" -notext -in "$ca_ocsp_dir/csr.pem" -out "$ca_ocsp_dir/cert.pem"
    cont $?
    puts "$ca_ocsp_dir/cert.pem"
}

function update_db {
    openssl_func ca "$batch_mode" -config "$ca_cnf" "${passin[@]}" -updatedb
    cont $?
}

function create_user_csr {
    user_cnf="$1" && shift
    name="$1" && shift

    openssl_func req "$batch_mode" -config "$user_cnf" -key "$ca_new_certs_dir/$name/key.pem" "${passin[@]}" -new -out "$ca_dir/csr/$name-csr.pem"
    cont $?
    puts "$ca_dir/csr/$name-csr.pem"
}

function sign_user_csr {
    issuer_dir="$1" && shift
    user_cnf="$1" && shift
    days="$1" && shift
    extension="$1" && shift
    modify="$( date_modify )"

    openssl_func ca "$batch_mode" $modify -config "$user_cnf" -extensions "$extension" "${passin[@]}" -days "$days" -notext -in "$ca_dir/csr/$name-csr.pem" -out "$ca_new_certs_dir/$name/cert.pem"
    cont $?
    puts "$ca_new_certs_dir/$name/cert.pem"
}

function convert_cert {
    input="$1" && shift
    basename=$(basename "$input")
    dirname=$(dirname "$input")
    filename="${basename%.*}"

    openssl_func x509 -outform der -in "$input" -out "$dirname/$filename.der"
    puts "$dirname/$filename.der"
    openssl x509 -noout -text -in "$input" > "$dirname/$filename.txt"
    puts "$dirname/$filename.txt"
}

function convert_csr {
    input="$1" && shift
    basename=$(basename "$input")
    dirname=$(dirname "$input")
    filename="${basename%.*}"

    openssl_func req -outform der -in "$input" -out "$dirname/$filename.der"
    puts "$dirname/$filename.der"
    openssl req -in "$input" -noout -text > "$dirname/$filename.txt"
    puts "$dirname/$filename.txt"
}

function convert_crl {
    input="$1" && shift
    basename=$(basename "$input")
    dirname=$(dirname "$input")
    filename="${basename%.*}"

    openssl_func crl -in "$input" -outform der -out "$dirname/$filename.der"
    puts "$dirname/$filename.der"
    openssl crl -in "$input" -noout -text > "$dirname/$filename.txt"
    puts "$dirname/$filename.txt"
}

function unfold_chain {
    input="$1" && shift
    basename=$(basename "$input")
    dirname=$(dirname "$input")

    input_data=$(cat "$input")
    (cd "$dirname" && \
        awk 'split_after==1{n++;split_after=0} /-----END CERTIFICATE-----/ {split_after=1} \
        {print > "ca." n+1 ".pem"}' <<< "$input_data")
    count=$(grep -c "END CERTIFICATE" "$input")
    for i in $(seq 1 "$count"); do
        puts "$dirname/ca.$i.pem"
    done
}

function update_crl {
    ca="$1" && shift

    load_ca "$ca"
    [ -z "${passin[*]}" ] && passin=("${passedout[@]}")
    openssl_func ca "$batch_mode" -config "$ca_cnf" "${passin[@]}" -gencrl -out "$ca_dir/crl/crl.pem"
    cont $?
    puts "$ca_dir/crl/crl.pem"

    convert_crl "$ca_dir/crl/crl.pem"
}

function revoke_ca_cert {
    use_ca "$issuer_dir"

    [ -z "${passin[*]}" ] && passin=("${passedout[@]}")
    openssl_func ca "$batch_mode" -config "$ca_cnf" "${passin[@]}" -revoke "$ca_certificate"
    cont $?
}

function revoke_client_cert {
    input="$1" && shift

    openssl_func ca "$batch_mode" -config "$ca_cnf" "${passin[@]}" -revoke "$input"
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

    puts "openssl ocsp -index $db -port $port -rsigner $rsigner -rkey $rkey -CA $ca_cert -text -out $log -ignore_err"
    openssl ocsp -index "$db" -port "$port" -rsigner "$rsigner" -rkey "$rkey" -CA "$ca_cert" -text -out "$log" -ignore_err
}
