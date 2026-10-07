#!/usr/bin/env bash
# Build config/mosquitto/passwd from the accounts defined in .env:
#   MQTT_BACKEND_PASSWORD and
#   MQTT_DEVICE_ACCOUNTS="<device_id>:<password>[,<device_id>:<password>...]"
# Restart the broker afterwards: docker compose restart mqtt-broker
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="eclipse-mosquitto@sha256:38c0da4f2ef84284d47b3b3eeea1cb3bdeabe81ee10caf0cd5c5ff61ee3ea408"

[[ -f "$ROOT/.env" ]] || { echo "Missing .env (copy .env.example)" >&2; exit 1; }
set -a; source "$ROOT/.env"; set +a

for var in MQTT_BACKEND_PASSWORD MQTT_DEVICE_ACCOUNTS; do
  [[ -n "${!var:-}" ]] || { echo "Missing $var in .env" >&2; exit 1; }
done

# user:password lines, hashed by mosquitto_passwd -U inside the broker image
plain="$(mktemp)"
trap 'rm -f "$plain"' EXIT
printf 'backend:%s\n' "$MQTT_BACKEND_PASSWORD" > "$plain"
IFS=',' read -ra accounts <<< "$MQTT_DEVICE_ACCOUNTS"
for account in "${accounts[@]}"; do
  [[ "$account" == *:?* ]] || { echo "Bad MQTT_DEVICE_ACCOUNTS entry: '${account%%:*}' (expected id:password)" >&2; exit 1; }
  printf '%s\n' "$account" >> "$plain"
done

docker run --rm -i --user "$(id -u):$(id -g)" --entrypoint sh "$IMAGE" \
  -c 'umask 077 && cat > /tmp/passwd && mosquitto_passwd -U /tmp/passwd && cat /tmp/passwd' \
  < "$plain" > "$ROOT/config/mosquitto/passwd"
chmod 644 "$ROOT/config/mosquitto/passwd"

echo "Wrote config/mosquitto/passwd ($(wc -l < "$ROOT/config/mosquitto/passwd") accounts)"
