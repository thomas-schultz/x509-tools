# x509-tool - Create CA, Intermediate-CA, Server and Client Certificates

```
Usage: ./x509-tool.sh [<options>] <command> <subcommand>
  commands:
    create ca <name>                  create root ca, default 'root'
    create intermediate <ca> <name>   create intermediate ca, default 'intermediate'
    create server|client <ca> <name>  create server or client certifacte:
    export server|client <name>       export end-user certificate
    revoke ca <ca> <name>             revoke intermediate certificate
    revoke server|client <ca> <name>  revoke server or client certificate
    update crl <name>                 update revocation list:

  options:
    -v/--verbose                  verbose output
    -p/--preset <file>            load presets from file
    -i/--interactive              load presets from file
    -b/--bits <number>            set key length
    -pw/--passphrase <pw>         set passphrase for private key
    -cp/--ca-passphrase <pw>          passphrase for private key of authority
    --ca-cnf <file>               openssl config for CAs
    --server-cnf <file>           openssl config for server certificates
    --client-cnf <file>           openssl config for client certificates
    --pkcs12 <pw>                 export client/server certs to pkcs12 file
    -KEY=VALUE                    C/ST/L/O/OU/CN/@/DNS
```
