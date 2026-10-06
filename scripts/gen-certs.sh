#!/usr/bin/env bash
# Generate the local CA and the Mosquitto server certificate for MQTTS.
#
#   ./scripts/gen-certs.sh [SERVER_IP]      (default: 192.168.10.1)
#
# The CA key stays in certs/ca/ (never mounted in a container). The broker
# gets ca.crt, server.crt and server.key in config/mosquitto/certs/.
# ca.crt is also what the firmware embeds to verify the broker.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_IP="${1:-192.168.10.1}"
CA_DIR="$ROOT/certs/ca"
BROKER_DIR="$ROOT/config/mosquitto/certs"
mkdir -p "$CA_DIR" "$BROKER_DIR"

if [[ ! -f "$CA_DIR/ca.key" ]]; then
  echo "Creating local CA in certs/ca/"
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
    -keyout "$CA_DIR/ca.key" -out "$CA_DIR/ca.crt" \
    -subj "/O=AetherCorp/CN=Sentinel-X Local CA" 2>/dev/null
  chmod 600 "$CA_DIR/ca.key"
else
  echo "Reusing existing CA in certs/ca/"
fi

echo "Creating broker certificate for IP $SERVER_IP"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
openssl req -newkey rsa:2048 -nodes -sha256 \
  -keyout "$BROKER_DIR/server.key" -out "$tmp/server.csr" \
  -subj "/O=AetherCorp/CN=mqtt-broker" 2>/dev/null
cat > "$tmp/server.ext" <<EOF
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
# DNS:$SERVER_IP too: the ESP32's mbedTLS 2.x only matches DNS names, not IP SANs
subjectAltName = IP:$SERVER_IP, DNS:$SERVER_IP, IP:127.0.0.1, DNS:mqtt-broker, DNS:localhost
EOF
openssl x509 -req -in "$tmp/server.csr" -days 825 -sha256 \
  -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" -CAcreateserial \
  -extfile "$tmp/server.ext" -out "$BROKER_DIR/server.crt" 2>/dev/null
cp "$CA_DIR/ca.crt" "$BROKER_DIR/ca.crt"

# The broker runs as uid 1883 and reads the key through a read-only mount.
chmod 644 "$BROKER_DIR/server.key" "$BROKER_DIR/server.crt" "$BROKER_DIR/ca.crt"

openssl verify -CAfile "$CA_DIR/ca.crt" "$BROKER_DIR/server.crt"
echo "Done. Paste certs/ca/ca.crt into the firmware's include/secrets.h (MQTT_CA_CERT)."
