# Standby edge TLS: signing Mac 4's certificate (Extension E)

The standby edge on Mac 4 must serve `app.teamX.test` with a certificate that
clients already trust. Clients trust one thing: the team root CA from Phase 1
(`02_config/teamX-rootCA.crt`). So Mac 2 signs Mac 4's certificate with that
same CA. No client needs to install anything new.

## Who holds what

| File | Lives on | Leaves that Mac? |
| --- | --- | --- |
| `teamX-rootCA.key` | Mac 2 only | Never |
| `teamX-rootCA.crt` | Repo and every client | Yes, it is public |
| `app.teamX.test-standby.key` | Mac 4 only | Never |
| `app.teamX.test-standby.csr` | Mac 4, copied to Mac 2 | Yes, it holds only the public key |
| `app.teamX.test-standby.crt` | Mac 2 signs it, copied to Mac 4 | Yes, it is public |

Why a CSR instead of copying keys: a private key proves identity. If the CA key
left Mac 2, anyone holding the copy could mint trusted certificates for any
name. If Mac 2 created Mac 4's key and sent it over, the key would have
existed on two machines. With a CSR, each private key is created on the
machine that uses it and never moves.

## 1. Mac 4 creates the key and CSR

```sh
02_config/phase2/mac4-standby-edge.sh --generate-csr
openssl req -in ~/cn-project/tls/app.teamX.test-standby.csr -noout -text | grep -E "Subject:|DNS:"
```

Send only `app.teamX.test-standby.csr` to Mac 2 (AirDrop or USB).

## 2. Mac 2 signs it with the team root CA

```sh
cd ~/cn-project/tls
cat > app.teamX.test-standby.ext <<'EOF'
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:app.teamX.test,DNS:api.teamX.test
EOF
openssl x509 -req -in app.teamX.test-standby.csr \
  -CA teamX-rootCA.crt -CAkey teamX-rootCA.key -CAserial teamX-rootCA.srl \
  -out app.teamX.test-standby.crt -days 365 -sha256 \
  -extfile app.teamX.test-standby.ext
```

The CSR asks for the SAN names, but `openssl x509 -req` ignores extensions in
the CSR. The `.ext` file is what actually puts the SANs and server usage into
the certificate. Without it, browsers and curl reject the certificate because
the hostname is not in the SAN.

## 3. Mac 2 verifies before sending

```sh
openssl verify -CAfile teamX-rootCA.crt app.teamX.test-standby.crt
openssl x509 -in app.teamX.test-standby.crt -noout -subject -issuer -ext subjectAltName
```

Expected: `app.teamX.test-standby.crt: OK`, issuer `teamX Local Root CA`, and
both `DNS:app.teamX.test` and `DNS:api.teamX.test`.

Send `app.teamX.test-standby.crt` back to Mac 4. Mac 4 places it at
`~/cn-project/tls/app.teamX.test-standby.crt` and runs
`02_config/phase2/mac4-standby-edge.sh <MAC3_IP>`, which checks the chain
against `02_config/teamX-rootCA.crt` before installing the config.

## Status

Pending on the real Macs: needs Mac 4's CSR. The same flow was exercised in
the Docker emulation with a throwaway lab CA (see
[05_docker_lab](../../05_docker_lab/README.md)); that does not prove the real
certificate exists.
