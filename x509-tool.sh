#!/bin/bash

# load libs
source "${BASH_SOURCE%/*}/lib/exitcodes.sh"
source "${BASH_SOURCE%/*}/lib/helper.sh"
source "${BASH_SOURCE%/*}/lib/ca.sh"
source "${BASH_SOURCE%/*}/lib/user.sh"


# args
batch_mode="-batch"

# use as random generator
rand="openssl rand -hex 8"

function show_usage {
    cat << EOF
usage:  $0 <command> <subcommand> [<args>] [<options>]
author: Thomas Schultz (thomas@t-schultz.de)
source: https://github.com/thomas-schultz/x509-tools

 define <type>:     defines or updates CA settings (presets.cnf)
    ca <folder>                 for Root-CAs
    subca <folder> <issuer>     for intermediate CAs
    subca <folder> <issuer>     for intermediate CAs which are
                                not alowed to sign further CAs

 create <type>:     creates x509 certificates
    ca <folder>                 Root-CA
    subca <folder>              Intermediate CA signed by
                                the CA of the <issuer> folder
    endca <folder>              Intermediate End-CA signed by
                                the CA of the <issuer> folder
    server <name> <issuer>      server certificate (according to ca.cnf)
    client <name> <issuer>      client certificate (according to ca.cnf)

 list <type>:       list x509 objects
    ca [<folder>]               lists all CAs or only the given one

 update <type>:     updates x509 objects
    crl <folder>                updates the CRL of the given CA
    ocsp <folder>               not yet implemented:
                                renews the ocsp signing certificate

 revoke <type>:     revokes a x509 objects
    ca <folder>                 revokes a intermediate CA
    client <name>               revokes a client certificate
                                (name can be folder or serial)
    server <name>               revokes a server certificate
                                (name can be folder or serial)

options:
    -h/--help               shows this output
    -v/--verbose            verbose output
    -i/--interactive        load presets from file
    -b/--bits <number>      set key length
    -d/--days <number>      set validity period in days
    -p/--policy <policy>    set the policy for the CA
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
        DNS/SAN:    subjaltname
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
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -v | --verbose)
            verbose=1
            ;;
        -i | --interactive)
            batch_mode=""
            ;;
        --passin)
            pw=$2 && shift
            passin="-passin pass:$pw"
            passedin="-passout pass:$pw"
            ;;
        --passout)
            pw=$2 && shift
            passout="-passout pass:$pw"
            passedout="-passin pass:$pw"
            ;;
        --pkcs12)
            pkcs12=$2 && shift
            pkcs12_passout="-passout pass:$pkcs12"
            ;;
        -subj)
            subj=$2 && shift
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
        -DNS|-SAN)
            set_value "subjaltname" "$VALUE"
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
        -p|--policy)
            export policy=$2 && shift
            ;;
        -b|--bits)
            export bits=$2 && shift
            ;;
        -d|--days)
            export days=$2 && shift
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
    action=$1 && shift
    sub=$1 && shift
    if [ -z "$sub" ]; then
        show_usage && exit 1
    fi

    case "$action" in
        define)
            define $sub $*
            ;;
        create)
            create $sub $*
            ;;
        list)
            list $sub $*
            ;;
        update)
            update $sub $*
            ;;
        revoke)
            revoke $sub $*
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
            [ -z $bits ] || export ca_keylength=$bits
            [ -z $days ] || export ca_days=$days
            define_ca $name
            ;;
        subca)
            [ -z $bits ] || export ca_keylength=$bits
            [ -z $days ] || export ca_days=$days
            [ -z $1 ] && echo "ERROR: missing issuer path for 'define $type'" && exit 1
            define_ca $name $*
            ;;
        endca)
            [ -z $bits ] || export ca_keylength=$bits
            [ -z $days ] || export ca_days=$days
            [ -z $1 ] && echo "ERROR: missing issuer path for 'define $type'" && exit 1
            define_ca $name $*
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
            [ -z $bits ] || export ca_keylength=$bits
            [ -z $days ] || export ca_days=$days
            create_ca $name
            ;;
        subca)
            [ -z $bits ] || export ca_keylength=$bits
            [ -z $days ] || export ca_days=$days
            create_sub_ca $name
            ;;
        endca)
            [ -z $bits ] || export ca_keylength=$bits
            [ -z $days ] || export ca_days=$days
            create_end_ca $name
            ;;
        server)
            [ -z $bits ] || export cert_keylength=$bits
            [ -z $days ] || export cert_days=$days
            [ -z $1 ] && echo "ERROR: missing issuer path for 'create $type'" && exit 1
            create_server_certificate $name $*
            ;;
        client)
            [ -z $bits ] || export cert_keylength=$bits
            [ -z $days ] || export cert_days=$days
            [ -z $1 ] && echo "ERROR: missing issuer path for 'create $type'" && exit 1
            create_client_certificate $name $*
            ;;
        *)
            echo "ERROR: unknown command 'create $type'" && exit 1
    esac
}

function list {
    type="$1" && shift

    case "$type" in
        ca)
            if [ -t $1 ]; then
                for file in `find . -name "presets.cnf"`; do
                    info_ca `dirname $file`
                done
            else
                info_ca $1
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
        update_crl $name
        ;;
    crl)
        update_crl $name
        ;;
    ocsp)
        echo "NOT YET IMPLEMENTED" && exit 1
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
            revoke_ca $name
            ;;
        subca)
            revoke_ca $name
            ;;
        endca)
            revoke_ca $name
            ;;
        server)
            [ -z $1 ] && echo "ERROR: missing issuer path for 'revoke $type'" && exit 1
            revoke_user_certificate $name $*
            ;;
        client)
            [ -z $1 ] && echo "ERROR: missing issuer path for 'revoke $type'" && exit 1
            revoke_user_certificate $name $*
            ;;
        *)
            echo "ERROR: unknown command 'revoke $type'" && exit 1
    esac
}

main ${FIXEDARGS[@]}
