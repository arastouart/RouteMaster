#!/usr/bin/env bash
#
# make_local_cert.sh — create a self-signed CODE-SIGNING certificate named
# "RouteMaster Local Dev" in the login keychain if it does not already exist.
#
# This lets RouteMaster be signed with Hardened Runtime TODAY, with no paid Apple
# Developer account. The LOCAL_DEV XPC code-signing requirements pin this cert's
# common name (see Sources/Shared/HelperConstants.swift).
#
# Idempotent: safe to run repeatedly.
set -euo pipefail

CERT_CN="RouteMaster Local Dev"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

echo "==> Checking for existing code-signing identity: ${CERT_CN}"
if security find-identity -v -p codesigning | grep -qF "${CERT_CN}"; then
  echo "    Already present. Nothing to do."
  exit 0
fi

echo "==> Creating self-signed code-signing certificate: ${CERT_CN}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

# OpenSSL config: a code-signing leaf (extendedKeyUsage=codeSigning).
cat > "${WORKDIR}/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no

[ dn ]
CN = ${CERT_CN}

[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# Generate key + self-signed cert.
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "${WORKDIR}/key.pem" \
  -out    "${WORKDIR}/cert.pem" \
  -days 3650 \
  -config "${WORKDIR}/cert.cnf" >/dev/null 2>&1

# Bundle into a PKCS#12 for import (empty password).
#
# macOS `security import` / SecKeychainItemImport only understands the LEGACY PKCS#12
# format. Modern OpenSSL (e.g. Homebrew's OpenSSL 3.x) defaults to a SHA-256 MAC and
# newer PBE algorithms, which macOS misreads as "MAC verification failed (wrong
# password?)". Emit the legacy MAC + PBE so the .p12 imports cleanly.
p12_export() {
  openssl pkcs12 -export \
    -inkey "${WORKDIR}/key.pem" \
    -in    "${WORKDIR}/cert.pem" \
    -name  "${CERT_CN}" \
    -out   "${WORKDIR}/cert.p12" \
    -passout pass: "$@"
}

# Preferred: force legacy algorithms explicitly (works on OpenSSL 1.1 and 3.x).
if ! p12_export -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES >/dev/null 2>&1; then
  echo "    (legacy PBE flags unsupported; retrying with -legacy provider)"
  # OpenSSL 3.x fallback: -legacy switches to the old provider defaults macOS accepts.
  if ! p12_export -legacy >/dev/null 2>&1; then
    echo "    (-legacy unsupported; falling back to default export)"
    p12_export >/dev/null 2>&1
  fi
fi

# Import key + cert into the login keychain, allowing codesign to use it non-interactively.
CODESIGN_BIN="$(command -v codesign || echo /usr/bin/codesign)"
security import "${WORKDIR}/cert.p12" \
  -k "${KEYCHAIN}" \
  -P "" \
  -T /usr/bin/codesign \
  -T /usr/bin/productsign \
  -T "${CODESIGN_BIN}" >/dev/null

# Trust the cert for code signing (best effort; may prompt for keychain password).
echo "==> Marking certificate as trusted for code signing (may prompt for your password)"
security add-trusted-cert -d -r trustAsRoot \
  -p codeSign \
  -k "${KEYCHAIN}" \
  "${WORKDIR}/cert.pem" 2>/dev/null || \
  echo "    (Could not auto-trust; codesign will still work for local dev.)"

# Allow codesign to access the key without an interactive prompt each build.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -k "" "${KEYCHAIN}" >/dev/null 2>&1 || true

echo "==> Done. Verify with:"
echo "    security find-identity -v -p codesigning | grep \"${CERT_CN}\""
