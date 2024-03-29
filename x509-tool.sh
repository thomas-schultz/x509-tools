#!/bin/bash

# load libs
# shellcheck source-path=SCRIPTDIR
base="$( cd "$( dirname "$( realpath "${BASH_SOURCE[0]}")" )" > /dev/null && pwd )"
if [ -z "$OPENSSL_CA_CNF" ]; then
    OPENSSL_CA_CNF="${base}/config/ca.cnf"
fi
if [ -z "$OPENSSL_CSR_CNF" ]; then
    OPENSSL_CSR_CNF="${base}/config/csr.cnf"
fi

VERSION='x509-tools 2023-06-15 11:15:23';
AUTHOR="Thomas Wild (thomas@t-schultz.de)"
REPO="https://github.com/thomas-schultz/x509-tools"

source "${base}/lib/helper.sh"
source "${base}/lib/openssl.sh"
source "${base}/lib/ca.sh"
source "${base}/lib/user.sh"


# args
export batch_mode="-batch"

# use as random generator
export rand="openssl rand -hex 8"

function show_usage {
    cat << EOF
author:  ${AUTHOR}
source:  ${REPO}
licence: $( sed -n '1p' LICENSE | xargs ) $( sed -n '2p' LICENSE | xargs )

usage:   ./x509-tool.sh <command> <subcommand> [<args>] [<options>]
 define <type>:     defines or updates CA settings (presets.cnf)
    ca <folder>                 for Root-CAs
    subca <folder> <issuer>     for intermediate CAs
    endca <folder> <issuer>     for intermediate CAs which are
                                not alowed to sign further CAs

 create <type>:     creates x509 certificates
    ca <folder>                 Root-CA
    subca <folder> <issuer>     Intermediate CA signed by
                                the CA of the <issuer> folder
    endca <folder> <issuer>     Intermediate End-CA signed by
                                the CA of the <issuer> folder
    server <name> <issuer>      server certificate (according to ca.cnf)
    client <name> <issuer>      client certificate (according to ca.cnf)
    signer <name> <issuer>      signer certificate (according to ca.cnf)

 export:            exports certificates in pkcs12 format
    user <name> <issuer>        only works on existing certificates

 list <type>:       list x509 objects
    ca [<folder>]               lists all CAs or only the given one

 update <type>:     updates x509 objects
    crl <folder>                updates the CRL of the given CA
    ocsp <folder>               updates the certificate revocation database

 revoke <type>:     revokes a x509 objects
    ca <folder>                 revokes a intermediate CA
    client <name>               revokes a client certificate
                                (name can be folder or serial)
    server <name>               revokes a server certificate
                                (name can be folder or serial)
    signer <name>               revokes a signer certificate
                                (name can be folder or serial)

 run ocsp <folder> <port>       runs an ocsp server

options:
    -h/--help               shows this output
    --version               shows version information
    -v/--verbose            verbose output
    -i/--interactive        interactive user inputs
    -b/--bits <number>      set key length
    -d/--days <number>      set validity period in days
    -p/--policy <policy>    set the policy for the CAv
    --startdate <date>      set the start date in YYYYMMDDHHMMSSZ
    --enddate <date>        set the end date in YYYYMMDDHHMMSSZ
    --ecdsa-curve <curve>   use specific ecdsa curve
    --ask                   ask for passwords
    --passin <pw>           set passphrase to unlock private key
    --passout <pw>          set passphrase for private key
    --pkcs12 <pw>           export client/server certs to pkcs12 file
    -subj <subject>         set x509 subject as string "/KEY=value/.."
    -KEY=value              allow to set individual variables
        C:          countryName
        ST:         stateOrProvinceName
        L:          localityName
        O:          organizationName
        OU:         organizationalUnitName
        CN:         commonName
        DNS:        subjaltname DNS
        IP:         subjaltname IP
        UPN:        subjaltname UPN (otherName)
        @/E:        emailAddress
        CRL:        crlUrl
        OCSP:       ocspUrl
        URL:        issuerUrl

EOF
}

if [ $# -eq 0 ]; then
  show_usage && exit 1
fi

FIXEDARGS=()
# parse args
while [ "$1" != "" ]; do
    PARAM=$(echo "$1" | awk -F= '{print $1}')
    VALUE=$(echo "$1" | awk -F= '{print $2}')
    case $PARAM in
        --version)
            echo "$VERSION ($REPO)" && exit 0
            ;;
        -v | --verbose)
            export verbose=1
            ;;
        -i | --interactive)
            export batch_mode=""
            ;;
        --ask)
            export passout=()
            export pkcs12=" "
            ;;
        --passin)
            export pw="$2" && shift
            export passin=(-passin "pass:$pw")
            export passedin=(-passout "pass:$pw")
            ;;
        --passout)
            export pw="$2" && shift
            export passout=(-passout "pass:$pw")
            export passedout=(-passin "pass:$pw")
            ;;
        --pkcs12)
            export pkcs12="$2" && shift
            export pkcs12_passout=(-passout "pass:$pkcs12")
            ;;
        --ecdsa-curve)
            ecdsa_curve="$2" && shift
            if [[ "${ecdsa_curve}" == 'ED25519' ]]; then
                [ -n "${pw}" ] && passout=(-pass "pass:${pw}")
                ecdsa_curve_genpkey=(-algorithm "${ecdsa_curve}")
                export ecdsa_curve_genpkey
            else
                ecdsa_curve_x509_tools=(-name "$ecdsa_curve")
                export ecdsa_curve_x509_tools
            fi
            ;;
        -subj)
            subj="$2" && shift
            set_subject "$subj"
            ;;
        -C)
            set_value "countryName" "$VALUE"
            ;;
        -ST)
            set_value "stateOrProvinceName" "$VALUE"
            ;;
        -L)
            set_value "localityName" "$VALUE"
            ;;
        -O)
            set_value "organizationName" "$VALUE"
            ;;
        -OU)
            set_value "organizationalUnitName" "$VALUE"
            ;;
        -CN)
            set_value "commonName" "$VALUE"
            ;;
        -DNS)
            set_value "subjaltnameDNS" "$VALUE"
            ;;
        -IP)
            set_value "subjaltnameIP" "$VALUE"
            ;;
        -UPN)
            set_value "subjaltnameUPN" "$VALUE"
            ;;
        -@|-E)
            set_value "emailAddress" "$VALUE"
            ;;
        -CRL)
            set_value "crlUrl" "$VALUE"
            ;;
        -OCSP)
            set_value "ocspUrl" "$VALUE"
            ;;
        -URL)
            set_value "issuerUrl" "$VALUE"
            ;;
        --startdate)
            export startdate="$2" && shift
            ;;
        --enddate)
            export enddate="$2" && shift
            ;;
        -p|--policy)
            export policy="$2" && shift
            ;;
        -b|--bits)
            export bits="$2" && shift
            ;;
        -d|--days)
            export days="$2" && shift
            ;;
        -h|--help)
            show_usage && exit 0
            ;;
        -*)
            echo "ERROR: unknown parameter \"$PARAM\"" && exit 1
            ;;
        *)
            FIXEDARGS+=("$1")
            ;;
    esac
    shift
done

function main {
    action="$1" && shift
    sub="$1" && shift
    if [ -z "$sub" ]; then
        show_usage && exit 1
    fi

    case "$action" in
        define)
            define "$sub" "$@"
            ;;
        create)
            create "$sub" "$@"
            ;;
        request)
            request "$sub" "$@"
            ;;
        export)
            export_cert "$sub" "$@"
            ;;
        list)
            list "$sub" "$@"
            ;;
        update)
            update "$sub" "$@"
            ;;
        revoke)
            revoke "$sub" "$@"
            ;;
        run)
            run "$sub" "$@"
            ;;
        *)
            echo "ERROR: unknown command '$action'" && exit 1
    esac
}

function define {
    type="$1" && shift
    name="$1" && shift

    case "$type" in
        ca)
            [ -z "$bits" ] || export ca_keylength="$bits"
            [ -z "$days" ] || export ca_days="$days"
            define_ca "$name"
            ;;
        subca)
            [ -z "$bits" ] || export ca_keylength="$bits"
            [ -z "$days" ] || export ca_days="$days"
            [ -z "$1" ] && echo "ERROR: missing issuer path for 'define $type'" && exit 1
            define_ca "$name" "$@"
            ;;
        endca)
            [ -z "$bits" ] || export ca_keylength="$bits"
            [ -z "$days" ] || export ca_days="$days"
            [ -z "$1" ] && echo "ERROR: missing issuer path for 'define $type'" && exit 1
            define_ca "$name" "$@"
            ;;
        *)
            echo "ERROR: unknown command 'define $type'" && exit 1
    esac
}

function create {
    type="$1" && shift
    name="$1" && shift

    case "$type" in
        ca)
            [ -z "$bits" ] || export ca_keylength="$bits"
            [ -z "$days" ] || export ca_days="$days"
            create_ca "$name"
            ;;
        subca)
            [ -z "$bits" ] || export ca_keylength="$bits"
            [ -z "$days" ] || export ca_days="$days"
            create_sub_ca "$name"
            ;;
        endca)
            [ -z "$bits" ] || export ca_keylength="$bits"
            [ -z "$days" ] || export ca_days="$days"
            create_end_ca "$name"
            ;;
        server)
            [ -z "$bits" ] || export cert_keylength="$bits"
            [ -z "$days" ] || export cert_days="$days"
            [ -z "$1" ] && echo "ERROR: missing issuer path for 'create $type'" && exit 1
            create_server_certificate "$name" "$@"
            ;;
        client)
            [ -z "$bits" ] || export cert_keylength="$bits"
            [ -z "$days" ] || export cert_days="$days"
            [ -z "$1" ] && echo "ERROR: missing issuer path for 'create $type'" && exit 1
            create_client_certificate "$name" "$@"
            ;;
        signer)
            [ -z "$bits" ] || export cert_keylength="$bits"
            [ -z "$days" ] || export cert_days="$days"
            [ -z "$1" ] && echo "ERROR: missing issuer path for 'create $type'" && exit 1
            create_signer_certificate "$name" "$@"
            ;;
        *)
            echo "ERROR: unknown command 'create $type'" && exit 1
    esac
}

function request {
    type="$1" && shift
    name="$1" && shift

    case "$type" in
        subca)
            [ -z "$bits" ] || export ca_keylength="$bits"
            [ -z "$days" ] || export ca_days="$days"
            create_sub_ca "$name"
            ;;
        endca)
            [ -z "$bits" ] || export ca_keylength="$bits"
            [ -z "$days" ] || export ca_days="$days"
            create_end_ca "$name"
            ;;
        server)
            [ -z "$bits" ] || export cert_keylength="$bits"
            [ -z "$days" ] || export cert_days="$days"
            [ -z "$1" ] && echo "ERROR: missing issuer path for 'create $type'" && exit 1
            create_server_certificate "$name" "$@"
            ;;
        client)
            [ -z "$bits" ] || export cert_keylength="$bits"
            [ -z "$days" ] || export cert_days="$days"
            [ -z "$1" ] && echo "ERROR: missing issuer path for 'create $type'" && exit 1
            create_client_certificate "$name" "$@"
            ;;
        *)
            echo "ERROR: unknown command 'request $type'" && exit 1
    esac
}

function export_cert {
    type="$1" && shift

    case "$type" in
        user|client|server|signer)
            [ -z "$1" ] && echo "ERROR: missing certificate name for 'export'" && exit 1
            [ -z "$2" ] && echo "ERROR: missing issuer path for 'export'" && exit 1
            export_pkcs12 "$@"
            ;;
        *)
            echo "ERROR: unknown command 'export $type'" && exit 1
    esac
}

function list {
    type="$1" && shift

    case "$type" in
        ca|subca)
            if [ -t "$1" ]; then
                find . -name "presets.cnf" -exec bash -c 'info_ca $(dirname "$0")' {} \;
            else
                info_ca "$1"
            fi
            ;;
        *)
            echo "ERROR: unknown command 'list $type'" && exit 1
    esac
}

function update {
  type="$1" && shift
  name="$1" && shift

  case "$type" in
    ca)
        update_crl "$name"
        update_ocsp "$name"
        ;;
    crl)
        update_crl "$name"
        ;;
    ocsp)
        update_ocsp "$name"
        ;;
    *)
        echo "ERROR: unknown command 'update $type'" && exit 1
  esac
}

function revoke {
    type="$1" && shift
    name="$1" && shift

    case "$type" in
        ca)
            revoke_ca "$name"
            ;;
        subca)
            revoke_ca "$name"
            ;;
        endca)
            revoke_ca "$name"
            ;;
        server)
            [ -z "$1" ] && echo "ERROR: missing issuer path for 'revoke $type'" && exit 1
            revoke_user_certificate "$name" "$@"
            ;;
        client)
            [ -z "$1" ] && echo "ERROR: missing issuer path for 'revoke $type'" && exit 1
            revoke_user_certificate "$name" "$@"
            ;;
        signer)
            [ -z "$1" ] && echo "ERROR: missing issuer path for 'revoke $type'" && exit 1
            revoke_user_certificate "$name" "$@"
            ;;
        *)
            echo "ERROR: unknown command 'revoke $type'" && exit 1
    esac
}

function run {
    type="$1" && shift

    case "$type" in
        ocsp)
            folder="$1" && shift
            port="$1" && shift

            run_ocsp_responder "$folder" "$port"
            ;;
        *)
            echo "ERROR: unknown command 'run $type'" && exit 1
    esac
}

main "${FIXEDARGS[@]}"
