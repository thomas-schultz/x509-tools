#!/bin/bash

# load libs
source "${BASH_SOURCE%/*}/lib_generic.sh"
source "${BASH_SOURCE%/*}/lib_ca.sh"
source "${BASH_SOURCE%/*}/lib_user.sh"


# set validation times
ca_days=7300
intm_days=1825
srv_days=380
client_days=380

# set key lengths
ca_bits=8192
intm_bits=4096
srv_bits=2048
client_bits=2048

# openssl config files
ca_cnf="ca.cnf"
srv_cnf="server.cnf"
client_cnf="client.cnf"

# set default for all options
srv_dir="server"
client_dir="client"

# args
batch_mode="-batch"

# use as random generator
rand="openssl rand -hex 8"

function show_usage {
  echo "Usage: $0 [<options>] <command> <subcommand>"
  echo "  commands:"
  echo "    create ca <name>                  create root ca, default 'root'"
  echo "    create intermediate <ca> <name>   create intermediate ca, default 'intermediate'"
  echo "    create server|client <ca> <name>  create server or client certifacte:"
  echo "    export server|client <name>       export end-user certificate"
  echo "    revoke ca <ca> <name>             revoke intermediate certificate"
  echo "    revoke server|client <ca> <name>  revoke server or client certificate"
  echo "    update crl <name>                 update revocation list:"
  echo ""
  echo "  options:"
  echo "    -v/--verbose                  verbose output"
  echo "    -p/--preset <file>            load presets from file"
  echo "    -i/--interactive              load presets from file"
  echo "    -b/--bits <number>            set key length"
  echo "    -pw/--passphrase <pw>         set passphrase for private key"
  echo "    -cp/--ca-passphrase <pw>      passphrase for private key of authority"
  echo "    --ca-cnf <file>               openssl config for CAs"
  echo "    --server-cnf <file>           openssl config for server certificates"
  echo "    --client-cnf <file>           openssl config for client certificates"
  echo "    --pkcs12 <pw>                 export client/server certs to pkcs12 file"
  echo "    -KEY=VALUE                    C/ST/L/O/OU/CN/@/CRL/DNS"
}

if [ $# -eq 0 ]; then
  show_usage
  exit 1
fi

FIXEDARGS=()
subjaltname_count=0
# parse args
while [ "$1" != "" ]; do
  PARAM=`echo $1 | awk -F= '{print $1}'`
  VALUE=`echo $1 | awk -F= '{print $2}'`
  case $PARAM in
    -v | --verbose)
      verbose=1
      ;;
    -p | --preset)
      preset=$2 && shift
      ;;
    -i | --interactive)
      batch_mode=""
      ;;
    -pw | --passphrase)
      pw=$2 && shift
      passout="-passout pass:$pw"
      passin="-passin pass:$pw"
      auth_passin="-passin pass:$pw"
      ;;
    -cp | --ca-passphrase)
      auth_pw=$2 && shift
      auth_passin="-passin pass:$auth_pw"
      ;;
    --ca-cnf)
      ca_cnf=$2 && shift
      ;;
    --server-cnf)
      srv_cnf=$2 && shift
      ;;
    --client-cnf)
      client_cnf=$2 && shift
      ;;
    --pkcs12)
      pkcs12=$2 && shift
      ;;
    -C)
      countryName=$VALUE
      ;;
    -ST)
      stateOrProvinceName=$VALUE
      ;;
    -L)
      localityName=$VALUE
      ;;
    -O)
      organizationName=$VALUE
      ;;
    -OU)
      organizationalUnitName=$VALUE
      ;;
    -CN)
      commonName=$VALUE
      ;;
    -@)
      emailAddress=$VALUE
      ;;
    -CRL)
      export "crlUrl=$VALUE"
      ;;
    -DNS)
      export "altName$subjaltname_count=$VALUE"
      subjaltname_count=$(( subjaltname_count + 1 ))
      ;;
    -b | --bits)
      bits=$2 && shift
      ;;
    -h | --help)
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
  read_presets
  case "$action" in
    create)
      create $*
      ;;
    revoke)
      revoke $*
      ;;
    update)
      update $*
      ;;
    export)
      export_pkcs12 $*
      ;;
    *)
      echo "ERROR: unknown action \"$action\" for main" && exit 1
  esac
}

function create {
  type=$1 && shift
  case "$type" in
    ca)
      create_ca $*
      ;;
    intermediate)
      create_intermediate $*
      ;;
    server)
      create_server $*
      ;;
    client)
      create_client $*
      ;;
    *)
      echo "ERROR: unknown type \"$type\" for create" && exit 1
  esac
}

function revoke {
  type=$1 && shift
  case "$type" in
    ca)
      revoke_ca $*
      ;;
    server)
      revoke_server $*
      ;;
    client)
      revoke_client $*
      ;;
    *)
      echo "ERROR: unknown type \"$type\" for revoke" && exit 1
  esac
}

function update {
  type=$1 && shift
  case "$type" in
    crl)
      update_crl $*
      ;;
    *)
      echo "ERROR: unknown type \"$type\" for update" && exit 1
  esac
}

main ${FIXEDARGS[@]}
