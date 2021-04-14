# x509-tool - Create CA, Intermediate-CA, Server and Client Certificates

[![pipeline status](https://gitlab.genua.de/twild/x509-tools/badges/master/pipeline.svg)](https://gitlab.genua.de/twild/x509-tools/commits/master)


This tool is a wrapper for openssl written for linux bash.


```
usage:  ./x509-tool.sh <command> <subcommand> [<args>] [<options>]
author: Thomas Schultz (thomas@t-schultz.de)
source: https://github.com/thomas-schultz/x509-tools

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
    ocsp <folder>               not yet implemented:
                                renews the ocsp signing certificate

 revoke <type>:     revokes a x509 objects
    ca <folder>                 revokes a intermediate CA
    client <name>               revokes a client certificate
                                (name can be folder or serial)
    server <name>               revokes a server certificate
                                (name can be folder or serial)
    signer <name>               revokes a signer certificate
                                (name can be folder or serial)

options:
    -h/--help               shows this output
    -v/--verbose            verbose output
    -i/--interactive        interactive user inputs
    -b/--bits <number>      set key length
    -d/--days <number>      set validity period in days
    -p/--policy <policy>    set the policy for the CAv
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
        DNS/SAN:    subjaltname
        @/E:        emailAddress
        CRL:        crlUrl
        OCSP:       ocspUrl
        URL:        issuerUrl



```

