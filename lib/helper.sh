#!/bin/bash

declare -A defaults=( \
        ["ca_keylength"]="8096" \
        ["cert_keylength"]="4096" \
        ["ca_days"]="7200" \
        ["crl_days"]="400" \
        ["cert_days"]="750" \
        ["policy"]="policy_strict" \
    )

subjaltname_count=0

function set_value {
    key=$1
    value=$2

    case "$key" in
        C|countryName)
            export countryName="$value"
            ;;
        ST|stateOrProvinceName)
            export stateOrProvinceName="$value"
            ;;
        L|localityName)
            export localityName="$value"
            ;;
        O|organizationName)
            export organizationName="$value"
            ;;
        OU|organizationalUnitName)
            export organizationalUnitName="$value"
            ;;
        CN|commonName)
            export commonName="$value"
            ;;
        SAN|subjaltname)
            export "altName${subjaltname_count}=$value"
            subjaltname_count=$(( subjaltname_count + 1 ))
            ;;
        E|emailAddress)
            export emailAddress="$value"
            ;;
        crl|crlUrl)
            export crlUrl="$value"
            ;;
        ocsp|ocspUrl)
            export ocspUrl="$value"
            ;;
        *)
            return
    esac
}

function set_subject {
    subj=$1
    while `echo "$subj" | grep '/.=.' >/dev/null`; do
        #echo "$subj"
        key=`echo "$subj" | sed -E 's/\/([^\/]?)=([^\/]*)(.*)?/\1/g'`
        value=`echo "$subj" | sed -E 's/\/([^\/]?)=([^\/]*)(.*)?/\2/g'`
        subj=`echo "$subj" | sed -E 's/\/([^\/]?)=([^\/]*)(.*)?/\3/g'`
        set_value "$key" "$value"
    done
}

function read_presets {
    preset=$1
    [ -z "$preset" ] && return
    if [ ! -e "$preset" ]; then
        echo "ERROR in read_presets(): no such file or diretory: $preset"
        exit 2
    fi
    unset issuer
    while IFS="=" read -r line; do
        [ -z "$line" ] || [[ "$line" =~ ^\#.* ]] && continue
        key=`echo "$line" | awk -F "=" '{print $1}' | awk '{gsub(/^ +| +$/,"")} {print $0}'`
        value=`echo "$line" | awk -F "=" '{print $2}' | awk '{gsub(/^ +| +$/,"")} {print $0}'`
        [ -z "$key" ] && continue
        [ -z "${!key}" ] || continue
        #echo "$key=$value"
        export "$key=$value"
    done < $preset
}

function set_defaults {
    for key in "${!defaults[@]}"; do
        [ -z "${!key}" ] || continue
        value="${defaults[$key]}"
        export "$key=$value"
    done
}

function prepare_config {
    ca_dir="$1" && shift
    issuer="$1" && shift
    #src="$1" && shift

    template="$ca_dir/ca.cnf"
    presets="$ca_dir/presets.cnf"
    puts "creating preset file $presets"
    echo -e "# presets for this CA\n" > $presets

    set_defaults

    # issuer path (none for Root-CAs)
    printf "%-20s = %s\n" "self" "$ca_dir" >> $presets
    [ -z $issuer ] && export issuer="$ca_dir"
    printf "%-20s = %s\n" "issuer" "$issuer" >> $presets

    puts "creating config file $template"
    cp "$OPENSSL_CA_CNF" "$template"
    template_config "$template" "$presets"
}

function template_config {
    template="$1" && shift
    presets="$1" && shift

    vars=`sed -n '/{{\(.*\)}}/p' $template | sed -E 's/.*\{\{\s+(.*)\s+\}\}.*/\1/'`
    for key in "${!defaults[@]}"; do
        vars=`echo -e "$vars\n$key"`
    done
    while read -r var; do
        value="${!var}"
        #echo "$var = $value"
        if [ -z "${value}" ]; then
            sed -i -E "/.*\{\{\s+${var//\//\\/}\s+\}\}.*/d" $template
        else
            [ -z $presets ] || grep "$var" $presets >/dev/null 2>&1 || printf "%-20s = %s\n" "$var" "$value" >> $presets
            sed -i -E "s/(.*)(\{\{\s+${var//\//\\/}\s+\}\})(.*)/\1${value//\//\\/}\3/" $template
        fi
    done <<< "$vars"

    # clean up entries if they are empty
    if [ -z "$crlUrl" ]; then
        sed -i -E "/.*crl_info.*/d" $template
        sed -i -E "/.*issuer_info.*/d" $template
    fi
    if [ -z "$ocspUrl" ]; then
        sed -i -E "/.*ocsp_info.*/d" $template
    fi
    if [ -z "$issuerUrl" ]; then
        sed -i -E "/.*issuer_info.*/d" $template
    fi
}

function prompt {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    LGRAY='\033[1;37m'
    NONE='\033[0m'
    if [ -z "$2" ]; then
        COLOR=$LGRAY
    else
        case $2 in
            "red")
            COLOR=$RED;;
            "green")
            COLOR=$GREEN;;
            *)
            COLOR=$NONE;;
        esac
    fi
    echo -e "${COLOR}$1${NONE}"
}

function puts {
    [ -z $verbose ] || echo "$1"
}

function cont {
    if [ $1 -ne 0 ]; then
        prompt "An error occurred, exited with code $1" red
        exit $1
    fi
}

function prepare_ca {
    ca_dir="$1"
    if [ -z "$ca_dir" ]; then
        echo "ERROR in prepare_ca(): no ca_dir" && exit 1
    fi
    export ca_dir="$ca_dir"
    export ca_cnf="$ca_dir/ca.cnf"
    read_presets "$ca_dir/presets.cnf"
    export issuer_dir="$issuer"
    export issuer_cnf="$issuer/ca.cnf"
    export ca_subj="CN="`grep commonName $ca_dir/presets.cnf | sed -e 's/.*=\s*\(\)/\1/'`
    export issuer_subj="CN="`grep commonName $issuer/presets.cnf | sed -e 's/.*=\s*\(\)/\1/'`
}

function restore_ca {
    prepare_ca "$sub_dir"
    passin=""
}

function use_ca {
    ca_dir="$1"
    if [ -z "$ca_dir" ]; then
        echo "ERROR in use_ca(): no ca_dir" && exit 1
    fi
    export ca_dir="$ca_dir"
    export ca_cnf="$ca_dir/ca.cnf"
}

function prepare_issuer {
    if [ -z "$issuer_dir" ]; then
        echo "ERROR in prepare_issuer(): no issuer_dir" && exit 1
    fi
    export sub_dir="$ca_dir"
    prepare_ca "$issuer_dir"
}

function append_sans {
    cnf="$1" && shift
    san="${1:-DNS}" && shift

    cp "$OPENSSL_CSR_CNF" "$cnf"
    template_config "$cnf"

    count=0
    [ -z "$altName$count" ] &&  sed -i '/subjectAltName/d' "$cnf"
    while true; do
        dns="altName$count"
        eval "val=\$$dns"
        [ -z "$val" ] && break
        puts "$dns = $val"
        echo "$san.${count} = $val" >> $cnf
        count=$(( count + 1 ))
    done
}

function extract_san_from_csr {
    cnf="$1" && shift
    csr="$1" && shift
    san="${1:-DNS}" && shift

    cp "$OPENSSL_CA_CNF" "$cnf"
    template_config "$cnf"

    list=`grep -i $san $csr | sed -e "s/$san:/\n/g" | sed 's/,//g'`
    count=0
    for dns in $list; do
        puts "$san.$count = $dns"
        echo "$san.$count = $dns" >> "$cnf"
        count=$(( count + 1 ))
    done
}
