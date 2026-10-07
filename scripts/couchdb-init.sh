#!/bin/sh
# One-shot CouchDB setup, run by the history-db-init service on every start.
# Idempotent: creates what is missing and updates the rest.
#   - authentication required on every request (except /_up)
#   - databases: _users, _replicator (single node), telemetry, events
#   - users: backend (role writer), ia (role reader)
#   - access: only members of those roles; only "writer" can write
#   - design docs: views for the graphs + write validation
# Passwords must not contain double quotes or backslashes (they go into JSON).
set -eu

URL="${COUCHDB_URL:-http://history-db:5984}"
AUTH="$COUCHDB_USER:$COUCHDB_PASSWORD"
DESIGN_DIR="${DESIGN_DIR:-/config/design}"

# PUT a JSON document, adding the current _rev when the document already exists.
put_doc() {
  path="$1"; body="$2"
  rev=$(curl -s -u "$AUTH" "$URL/$path" | sed -n 's/.*"_rev":"\([^"]*\)".*/\1/p')
  if [ -n "$rev" ]; then
    body=$(printf '%s' "$body" | sed "0,/{/s//{\"_rev\":\"$rev\",/")
  fi
  code=$(curl -s -o /tmp/resp -w '%{http_code}' -u "$AUTH" -X PUT "$URL/$path" \
    -H 'Content-Type: application/json' --data-binary "$body")
  case "$code" in
    200|201|202) echo "  ok    $path" ;;
    *) echo "  FAIL  $path ($code): $(cat /tmp/resp)"; exit 1 ;;
  esac
}

echo "Waiting for CouchDB at $URL..."
i=0
until curl -sf "$URL/_up" >/dev/null; do
  i=$((i + 1))
  [ "$i" -ge 60 ] && { echo "CouchDB not reachable after 60 s"; exit 1; }
  sleep 1
done

echo "Server config"
# Every request needs a valid user, except the /_up health check.
# Stored in the container's local.ini, so it is re-applied on every start.
curl -sf -u "$AUTH" -X PUT "$URL/_node/_local/_config/chttpd/require_valid_user_except_for_up" \
  -d '"true"' >/dev/null || { echo "  FAIL  require_valid_user_except_for_up"; exit 1; }
echo "  ok    require_valid_user_except_for_up"

echo "Databases"
# q=1: one shard per database (single node), so the _changes feed read by
# ia-prediction stays in write order. Only applies when a database is created.
for db in _users _replicator telemetry events; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -u "$AUTH" -X PUT "$URL/$db?q=1")
  case "$code" in
    201|202) echo "  created $db" ;;
    412) echo "  exists  $db" ;;
    *) echo "  FAIL  $db ($code)"; exit 1 ;;
  esac
done

echo "Users"
put_doc "_users/org.couchdb.user:backend" \
  "{\"name\":\"backend\",\"password\":\"$COUCHDB_BACKEND_PASSWORD\",\"roles\":[\"writer\"],\"type\":\"user\"}"
put_doc "_users/org.couchdb.user:ia" \
  "{\"name\":\"ia\",\"password\":\"$COUCHDB_IA_PASSWORD\",\"roles\":[\"reader\"],\"type\":\"user\"}"

echo "Access rules and design docs"
security='{"admins":{"names":[],"roles":[]},"members":{"names":[],"roles":["writer","reader"]}}'
for db in telemetry events; do
  put_doc "$db/_security" "$security"
  put_doc "$db/_design/security" "$(cat "$DESIGN_DIR/security.json")"
done
put_doc "telemetry/_design/telemetry" "$(cat "$DESIGN_DIR/telemetry.json")"

echo "CouchDB ready."
