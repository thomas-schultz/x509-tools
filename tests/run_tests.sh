#!/bin/bash

cd "${BASH_SOURCE%/*}" || exit
. ./testtool.sh

OUT="test.t"

if [ "$1" == "-v" ]; then
    verbose="-v"
else
    verbose=""
fi


function test_create_ca {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    rm -rf root-ca
    ./x509-tool.sh $verbose define ca root-ca -C="DE" -ST="City" -O="DotOrg" -CN="Thomas Root-CA" -E="mail@testing.org" -b 2048 -p policy_strict; it $? ${FUNCNAME[0]}
    [ -z "$verbose" ] || cat root-ca/presets.cnf
    ./x509-tool.sh $verbose create ca root-ca --passout Password1; it $? ${FUNCNAME[0]}
}

function test_create_ca_with_crl {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    rm -rf root-ca
    export crlUrl="http://crl.localhost"
    ./x509-tool.sh $verbose define ca root-ca -C="DE" -ST="state" -O="DotOrg" -CN="Thomas Root-CA" -E="mail@testing.org" -b 2048 -d 7200 -p policy_strict; it $? ${FUNCNAME[0]}
    [ -z "$verbose" ] || cat root-ca/presets.cnf
    ./x509-tool.sh $verbose create ca root-ca --passout Password1; it $? ${FUNCNAME[0]}
}

function test_create_ca_with_ocsp {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    rm -rf root-ca
    export ocspUrl="http://ocsp.localhost"
    export issuerUrl="http://ca.localhost"

    export crl_validity=365
    ./x509-tool.sh $verbose define ca root-ca -C="DE" -ST="state" -O="DotOrg" -CN="Thomas Root-CA" -E="mail@testing.org" -b 2048 -d 1200 -p policy_strict; it $? ${FUNCNAME[0]}
    [ -z "$verbose" ] || cat root-ca/presets.cnf
    ./x509-tool.sh $verbose create ca root-ca --passout Password1; it $? ${FUNCNAME[0]}
}

function test_create_ca_with_crl_and_ocsp {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    rm -rf root-ca
    export crlUrl="http://crl.localhost"
    export ocspUrl="http://ocsp.localhost"
    export issuerUrl="http://ca.localhost"

    export crl_validity=365
    ./x509-tool.sh $verbose define ca root-ca -C="DE" -ST="state" -O="DotOrg" -CN="Thomas Root-CA" -E="mail@testing.org" -b 2048 -d 7200 -p policy_strict; it $? ${FUNCNAME[0]}
    [ -z "$verbose" ] || cat root-ca/presets.cnf
    # Don't use passout here, because ocsp server does not support passin.
    ./x509-tool.sh $verbose create ca root-ca; it $? ${FUNCNAME[0]}
}

function test_create_subca {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    export crlUrl="http://crl.localhost/sub"
    export ocspUrl="http://ocsp.localhost/sub"
    export issuerUrl="http://ca.localhost/sub"

    rm -rf sub-ca
    ./x509-tool.sh $verbose define subca sub-ca root-ca -C="DE" -ST="state" -O="DotOrg" -CN="Testing Sub-CA1" -E="mail@testing.org" -b 2048 -d 3600 -p policy_loose; it $? ${FUNCNAME[0]}
    [ -z "$verbose" ] || cat sub-ca/presets.cnf
    ./x509-tool.sh $verbose create subca sub-ca --passin Password1 --passout Password2; it $? ${FUNCNAME[0]}
}

function test_create_subca2_fails {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    rm -rf sub2-ca
    ./x509-tool.sh $verbose define subca sub2-ca root-ca -C="DE" -ST="state" -O="DotOtherOrg" -CN="Testing Sub-CA2" -E="mail@testing.org" -b 2048 -d 3600 -p policy_loose; it $? ${FUNCNAME[0]}
    [ -z "$verbose" ] || cat sub2-ca/presets.cnf
    ./x509-tool.sh $verbose create subca sub2-ca --passin Password1 --passout Password2; nit $? ${FUNCNAME[0]}
}

function test_create_endca {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    rm -rf end-ca
    ./x509-tool.sh $verbose define endca end-ca sub-ca -C="DE" -ST="state" -O="DotOrg" -CN="Testing End-CA" -E="mail@testing.org" -b 3072 -d 3600 -p policy_loose; it $? ${FUNCNAME[0]}
    [ -z "$verbose" ] || cat end-ca/presets.cnf
    ./x509-tool.sh $verbose create endca end-ca --passin Password2 --passout Password3; it $? ${FUNCNAME[0]}
}

function test_revoke_endca {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose revoke subca end-ca --passin Password2; it $? ${FUNCNAME[0]}
}

function test_create_server {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose create server webserver1 sub-ca -d 120 --passin Password2 -CN="webserver1" -E="webserver1@dotorg.tld"; it $? ${FUNCNAME[0]}
}

function test_create_server_with_san {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose create server webserver2 sub-ca --passin Password2 -CN="webserver2" -DNS="webserver2.foo" -E="webserver2@dotorg.tld"; it $? ${FUNCNAME[0]}
}

function test_create_server_with_two_sans {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose create server webserver3 end-ca --passin Password3 -CN="webserver3" -DNS="webserver3.foo" -DNS="webserver3.bar" -E="webserver3@dotorg.tld"; it $? ${FUNCNAME[0]}
}

function test_create_client {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose create client client1 sub-ca --pkcs12 "passphrase" -d 120 --passin Password2 -CN="client1" -E="client1@dotorg.tld"; it $? ${FUNCNAME[0]}
}

function test_create_client_with_san {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose create client client2 end-ca --passin Password3 -CN="client2" -DNS="client2.foo" -E="client2@dotorg.tld"; it $? ${FUNCNAME[0]}
}

function test_create_client_with_two_sans {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose create client client3 end-ca --passin Password3 -CN="client3" -DNS="client3.foo" -DNS="client3.bar" -E="client3@dotorg.tld"; it $? ${FUNCNAME[0]}
}

function test_create_client_with_dns_and_ip {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose create client client4 end-ca --passin Password3 -CN="client4" -DNS="client4.foo" -IP="1.2.3.4" -E="client4@dotorg.tld"; it $? ${FUNCNAME[0]}
}

function test_create_client_with_san_and_upn {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose create client client5 end-ca --passin Password3 -CN="client5" -DNS="client5.foo" -UPN="client5" -E="client5@dotorg.tld"; it $? ${FUNCNAME[0]}
}

function test_revoke_client {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose revoke client sub-ca "client1" --passin Password2 ; it $? ${FUNCNAME[0]}
}

function test_update_ca_crl {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose update crl root-ca --passin Password1 ; it $? ${FUNCNAME[0]}
}

function test_update_ca_ocsp {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose update ocsp root-ca --passin Password1 ; it $? ${FUNCNAME[0]}
}

function test_update_ca {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose update ca root-ca --passin Password1 ; it $? ${FUNCNAME[0]}
}

function test_list_ca {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose list ca root-ca; it $? ${FUNCNAME[0]}
}

function test_list_subca {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose list subca sub-ca; it $? ${FUNCNAME[0]}
}

function test_run_ocsp_responder {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh "$verbose" run ocsp root-ca 9080 &
    pid=$!
    it $? "${FUNCNAME[0]}"
    kill "$pid"
}

function test_create_ca_special_characters {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    # ca_subject="\n "  # Line breaks or spaces at the end are unsupported
    ca_subject="Root \$HOME CA\"😀"
    rm -rf "$ca_subject"
    ./x509-tool.sh $verbose define ca "$ca_subject" -C="DE" -ST="City" -O="DotOrg" -CN="Thomas Root-CA" -E="mail@testing.org" -b 2048 -p policy_strict; it $? ${FUNCNAME[0]}
    [ -z "$verbose" ] || cat "$ca_subject"/presets.cnf
    ./x509-tool.sh $verbose create ca "$ca_subject" --passout Password1; it $? ${FUNCNAME[0]}
}

function test_create_client_special_characters {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ca_subject="Root \$HOME CA\"😀"
    # client_subject="\$HOME\n"  # Line breaks or dollars in subject are unsupported
    client_subject="Client @\"😀 "
    ./x509-tool.sh $verbose create client "$client_subject" "$ca_subject" --pkcs12 "passphrase" -d 120 --passin Password1 -CN="$client_subject" -E="client1@dotorg.tld"; it $? ${FUNCNAME[0]}
}


echo -e "\n#test $(date)" > $OUT

test_create_ca
test_create_ca_with_crl
test_create_ca_with_ocsp
test_create_ca_with_crl_and_ocsp
test_create_subca
test_create_subca2_fails
test_create_endca
test_revoke_endca
test_create_server
test_create_server_with_san
test_create_server_with_two_sans
test_create_client
test_create_client_with_san
test_create_client_with_two_sans
test_create_client_with_dns_and_ip
test_create_client_with_san_and_upn
test_revoke_client
test_update_ca_crl
test_update_ca_ocsp
test_update_ca
test_list_ca
test_list_subca
test_run_ocsp_responder
test_create_ca_special_characters
test_create_client_special_characters

cat $OUT
openssl version

[ $GOOD -eq $COUNT ] && exit 0
