# x509-tool - Create CA, Intermediate-CA, Server and Client Certificates

```
Usage: ./x509-tool.sh
  create root or intermediate ca:
    create ca|intermediate
  create server or client certifacte:
    create server|client <name> [<options>]
      --pkcs12  export to pkcs12 file
  export end-user certificate
    update server|client <name>
  revoke certificate:
    revoke intermediate
    revoke server|client <name>
  update revocation list:
    update ca|intermediate
```
