#!/usr/bin/env bash
# Jednorázově vytvoří self-signed code-signing certifikát "StatusBar Dev"
# a vloží ho do login klíčenky. Stabilní podpisová identita = "Always Allow"
# u Claude OAuth položky vydrží napříč rebuildy (konec opakovaných promptů).
set -euo pipefail

CERT_NAME="StatusBar Dev"
KEYCHAIN="$(security default-keychain | tr -d ' "')"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

setup_partition_list() {
  # Povolí codesignu přístup k privátnímu klíči bez GUI promptů.
  # Vyžádá si jednou heslo ke klíčence (= tvé přihlašovací heslo k Macu).
  echo "→ Nastavuji partition list (codesign pak nebude promptovat)…"
  echo "  Zadej heslo ke klíčence 'login' (tvé přihlašovací heslo k Macu):"
  if security set-key-partition-list -S apple-tool:,apple: -s \
       -l "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "✓ Partition list nastaven."
  else
    echo "⚠ Partition list se nepodařilo nastavit (špatné heslo?). Spusť skript znovu."
    exit 1
  fi
}

if security find-identity -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "✓ Identity '$CERT_NAME' už existuje."
  setup_partition_list
  exit 0
fi

cat > "$WORK/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $CERT_NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "→ Generuji self-signed cert + klíč…"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 3650 -config "$WORK/cert.cnf" 2>/dev/null

# -legacy: openssl 3.x jinak použije PKCS12 MAC, který macOS Security neumí přečíst
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$CERT_NAME" -out "$WORK/cert.p12" -passout pass:statusbar

echo "→ Importuji do '$KEYCHAIN'…"
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "statusbar" \
  -T /usr/bin/codesign -T /usr/bin/security

echo "✓ Hotovo. Ověření:"
security find-identity -p codesigning | grep "$CERT_NAME" || {
  echo "✗ Identity se nenašla. Zkontroluj EKU."; exit 1; }

setup_partition_list
