<!-- ABOUTME: TLS certificate setup notes for the Mac 2 edge: team CA, server certificate, client trust and validation. -->
<!-- ABOUTME: Part of the Phase 1 configuration bundle; every command here was run on Mac 2 on 28 September 2026. -->

# TLS setup notes (Mac 2 edge)

Mac 2 (`10.7.22.227`) terminates HTTPS for `app.teamX.test` and
`api.teamX.test` with a certificate signed by the team's own root CA. Clients
trust the root CA once; the server certificate can then be reissued without
touching any client.

**The CA private key (`teamX-rootCA.key`) was never shared.** It stays in
`~/cn-project/tls/` on Mac 2 and is not in this repository. Only the public
`teamX-rootCA.crt` is distributed.

## 1. Tools

OpenSSL 3 from Homebrew is required. The macOS built-in LibreSSL does not
support `-addext`.

```sh
brew install nginx openssl@3
export PATH="$(brew --prefix openssl@3)/bin:$PATH"
openssl version          # OpenSSL 3.x
mkdir -p ~/cn-project/tls && cd ~/cn-project/tls
```

## 2. Team root CA

```sh
openssl genrsa -out teamX-rootCA.key 4096
openssl req -x509 -new -key teamX-rootCA.key -sha256 -days 365 -out teamX-rootCA.crt \
  -subj "/CN=teamX Local Root CA/O=CN Project teamX" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"
```

Issued 28 Sep 2026 03:41 GMT, valid until 28 Sep 2027.

## 3. Server certificate

```sh
openssl genrsa -out app.teamX.test.key 2048
openssl req -new -key app.teamX.test.key -out app.teamX.test.csr \
  -subj "/CN=app.teamX.test/O=CN Project teamX"

cat > app.teamX.test.ext <<'EOF'
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:app.teamX.test,DNS:api.teamX.test
authorityKeyIdentifier=keyid,issuer
EOF

openssl x509 -req -in app.teamX.test.csr -CA teamX-rootCA.crt -CAkey teamX-rootCA.key \
  -CAcreateserial -out app.teamX.test.crt -days 365 -sha256 -extfile app.teamX.test.ext
```

Why these fields:

| Field | Reason |
|---|---|
| `subjectAltName` | Browsers and curl match the hostname against the SAN, not the CN. |
| `extendedKeyUsage=serverAuth` | macOS rejects server certificates without it. |
| `-days 365` | macOS rejects server certificates valid for more than 825 days. |
| RSA 2048 / SHA-256 | Accepted by current macOS, Safari and Chrome. |

Steps 2 and 3 are automated in `mac2-edge-setup.sh`, which reuses an existing
CA so clients never need to trust a second one.

## 4. nginx

The server block in `nginx-teamX.conf` (installed as
`/opt/homebrew/etc/nginx/servers/teamX.conf`) uses:

```nginx
listen 443 ssl;
http2 on;
ssl_certificate     /Users/sarveshsrinath/cn-project/tls/app.teamX.test.crt;
ssl_certificate_key /Users/sarveshsrinath/cn-project/tls/app.teamX.test.key;
ssl_protocols TLSv1.2 TLSv1.3;
```

Port 80 returns `301` to HTTPS. nginx reads certificate files only at start or
reload, so run `sudo nginx -s reload` after reissuing the certificate.

```sh
sudo nginx -t && sudo nginx      # first start
sudo nginx -s reload             # after any config or certificate change
```

## 5. Client trust

Send only `teamX-rootCA.crt` to each client (AirDrop). On every Mac, Mac 2
included:

```sh
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ~/Downloads/teamX-rootCA.crt
```

GUI alternative: Keychain Access, System keychain, drag the file in, open it,
Trust, Always Trust. Restart the browser afterwards. Safari and Chrome use the
keychain; Firefox keeps its own store and is not used for the demo.

If curl still reports `unable to get local issuer certificate`, pass
`--cacert ~/Downloads/teamX-rootCA.crt`. That still validates the certificate
fully. `curl -k` is never used.

## 6. Validation

```sh
# certificate chains to the team CA and carries both names
openssl verify -CAfile teamX-rootCA.crt app.teamX.test.crt          # app.teamX.test.crt: OK
openssl x509 -in app.teamX.test.crt -noout -subject -issuer -ext subjectAltName

# live handshake by hostname, no -k
curl -v https://app.teamX.test/api/status 2>&1 | grep -E "SSL connection|ALPN|subject|issuer|verify"
# TLSv1.3, "ALPN: server accepted h2", "SSL certificate verify ok."

curl -sI --http1.1 https://app.teamX.test/api/status | head -1      # HTTP/1.1 200
curl -sI           https://app.teamX.test/api/status | head -1      # HTTP/2 200

openssl s_client -connect 10.7.22.227:443 -servername app.teamX.test \
  -CAfile teamX-rootCA.crt </dev/null 2>/dev/null | grep -E "Protocol|Verify return"
# Protocol: TLSv1.3, Verify return code: 0 (ok)

# the certificate nginx serves is the one on disk
openssl s_client -connect 10.7.22.227:443 -servername app.teamX.test </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256
openssl x509 -in app.teamX.test.crt -noout -fingerprint -sha256
```

Before Mac 1's DNS is live, add `--resolve app.teamX.test:443:10.7.22.227`
to the curl commands. It skips DNS only; SNI and certificate validation still
use the hostname.

For the Wireshark capture of the Certificate message, use
`curl --tls-max 1.2`. In TLS 1.3 the certificate is encrypted.

Evidence: `04_evidence/E_tls/E-01_mac2_ca_and_cert_created.png`.
