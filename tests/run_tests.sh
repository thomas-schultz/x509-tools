#!/bin/bash

. ./testtool.sh

OUT="test.t"
COUNT=1

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
    ./x509-tool.sh $verbose create ca root-ca --passout Password1; it $? ${FUNCNAME[0]}
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
    ./x509-tool.sh $verbose create server webserver1 sub-ca -d 120 --passin Password2 -CN="foo1" -E="foobar@domain.tld"; it $? ${FUNCNAME[0]}
}

function test_create_server_with_san {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose create server webserver2 sub-ca --passin Password2 -CN="foo2" -DNS="foobar" -E="foobar@domain.tld"; it $? ${FUNCNAME[0]}
}

function test_create_server_with_two_sans {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose create server webserver3 end-ca --passin Password3 -CN="foo3" -DNS="foobar" -DNS="foo.bar" -E="foobar@domain.tld"; it $? ${FUNCNAME[0]}
}

function test_create_client {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose create client client1 sub-ca --pkcs12 "passphrase" -d 120 --passin Password2 -CN="c1" -E="foobar@domain.tld"; it $? ${FUNCNAME[0]}
}

function test_create_client_with_san {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose create client client2 end-ca --passin Password3 -CN="c2" -DNS="foobar" -E="foobar@domain.tld"; it $? ${FUNCNAME[0]}
}

function test_create_client_with_two_sans {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose create client client3 end-ca --passin Password3 -CN="c3" -DNS="foobar" -DNS="foo.bar" -E="foobar@domain.tld"; it $? ${FUNCNAME[0]}
}

function test_revoke_client {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose revoke client sub-ca "client1" --passin Password2 ; it $? ${FUNCNAME[0]}
}

function test_update_ca_crl {
    echo -e "\ntesting ${FUNCNAME[0]}\n"
    ./x509-tool.sh $verbose update ca root-ca --passin Password1 ; it $? ${FUNCNAME[0]}
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
test_revoke_client
test_update_ca_crl

cat $OUT
