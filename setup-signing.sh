#!/usr/bin/env bash
# Create a stable self-signed code-signing identity so the app's code identity
# (and thus its keychain ACL) stays constant across rebuilds.
set -euo pipefail

CERT_NAME="LimitHUD Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "$CERT_NAME"; then
  echo "✓ signing identity already exists: $CERT_NAME"
  exit 0
fi

DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT

cat > "$DIR/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CERT_NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "==> generating key + self-signed code-signing cert"
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout "$DIR/key.pem" -out "$DIR/cert.pem" -config "$DIR/cert.cnf" >/dev/null 2>&1

# -legacy makes OpenSSL 3 emit a SHA1-MAC / 3DES p12 that Apple's Security can import.
echo "==> packaging identity (legacy p12 for macOS compatibility)"
openssl pkcs12 -export -legacy -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
  -out "$DIR/identity.p12" -name "$CERT_NAME" -passout pass:limithud 2>/dev/null \
  || openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
       -out "$DIR/identity.p12" -name "$CERT_NAME" \
       -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -passout pass:limithud

echo "==> importing into login keychain (codesign granted key access)"
security import "$DIR/identity.p12" -k "$KEYCHAIN" -P limithud -T /usr/bin/codesign

echo "✓ created self-signed code-signing identity: $CERT_NAME"
