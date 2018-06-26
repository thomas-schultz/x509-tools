#!/bin/bash

if [ -z $1 ]; then
	echo "usage $0 <pkcs12-file>"
	exit 1
fi

read -sp 'PKCS12 Passphrase: ' passvar
openssl pkcs12 -in $1 -passin pass:$passvar -nocerts -out key.pem
openssl pkcs12 -in $1 -passin pass:$passvar -clcerts -nokeys -out cert.pem
openssl pkcs12 -in $1 -passin pass:$passvar -cacerts -nokeys -chain -out chain.pem
