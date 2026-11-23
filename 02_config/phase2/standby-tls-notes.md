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
| `app.teamX.test-standby.csr` | Mac 4, committed to the repo | Yes, it holds only the public key |
| `app.teamX.test-standby.crt` | Mac 2 signs it, committed to the repo | Yes, it is public |

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

Commit only the CSR, at `02_config/phase2/app.teamX.test-standby.csr`. The
key stays in `~/cn-project/tls` on Mac 4.

## 2. Mac 2 signs it with the team root CA

macOS ships LibreSSL as `/usr/bin/openssl`, which rejects `-ext` in step 3.
Put Homebrew OpenSSL 3 first on `PATH`, as in Phase 1's
[tls_setup_notes.md](../tls_setup_notes.md). Run steps 2 and 3 in the same
terminal.

```sh
export PATH="$(brew --prefix openssl@3)/bin:$PATH"
cp 02_config/phase2/app.teamX.test-standby.csr ~/cn-project/tls/   # from the repo root
cd ~/cn-project/tls
cat > app.teamX.test-standby.ext <<'EOF'
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:app.teamX.test,DNS:api.teamX.test
authorityKeyIdentifier=keyid,issuer
EOF
openssl x509 -req -in app.teamX.test-standby.csr \
  -CA teamX-rootCA.crt -CAkey teamX-rootCA.key -CAcreateserial \
  -out app.teamX.test-standby.crt -days 365 -sha256 \
  -extfile app.teamX.test-standby.ext
```

The CSR asks for the SAN names, but `openssl x509 -req` ignores extensions in
the CSR. The `.ext` file is what actually puts the SANs and server usage into
the certificate. Without it, browsers and curl reject the certificate because
the hostname is not in the SAN.

## 3. Mac 2 verifies, then commits the certificate

```sh
openssl verify -CAfile teamX-rootCA.crt app.teamX.test-standby.crt
openssl x509 -in app.teamX.test-standby.crt -noout -subject -issuer -ext subjectAltName
```

Expected: `app.teamX.test-standby.crt: OK`, issuer `teamX Local Root CA`, and
both `DNS:app.teamX.test` and `DNS:api.teamX.test`.

Copy the certificate into the repo and commit it at
`02_config/phase2/app.teamX.test-standby.crt`:

```sh
cp ~/cn-project/tls/app.teamX.test-standby.crt 02_config/phase2/   # from the repo root
```

Mac 4 pulls it, copies it to `~/cn-project/tls/app.teamX.test-standby.crt`,
and runs `02_config/phase2/mac4-standby-edge.sh <MAC3_IP>`, which checks the
chain against `02_config/teamX-rootCA.crt` and that the certificate matches
the key before installing the config.

## Verification output

Mac 2 signed Mac 4's CSR on 23 Nov 2026 with OpenSSL 3.6.3. Step 3 output:

```text
app.teamX.test-standby.crt: OK
subject=CN=app.teamX.test, O=CN Project teamX
issuer=CN=teamX Local Root CA, O=CN Project teamX
X509v3 Subject Alternative Name:
    DNS:app.teamX.test, DNS:api.teamX.test
```

Serial `41C5F4AD3029B5FE384B1D6584AEAB1443925F20`, valid until 23 Nov 2027.
The public key in the certificate matches the one in Mac 4's CSR, so it
pairs with the private key that stayed on Mac 4.

Pending: Mac 4 installs the certificate and serves trusted HTTPS from the
standby edge.
