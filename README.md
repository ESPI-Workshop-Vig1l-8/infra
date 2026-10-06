# Sentinel-X — infra

Docker Compose stack for the Sentinel-X "PC Serveur Local": Mosquitto (MQTT broker), CouchDB (telemetry history), the Go backend, the dashboard and the AI services.

## Setup

```bash
cp .env.example .env                 # then fill in the passwords
./scripts/gen-certs.sh 192.168.10.1  # TLS: local CA + broker certificate for the server IP
./scripts/mqtt-passwd.sh             # MQTT accounts from .env -> config/mosquitto/passwd
docker compose up -d
```

- `gen-certs.sh` keeps the CA key in `certs/ca/` (never mounted in a container) and puts `ca.crt`, `server.crt` and `server.key` in `config/mosquitto/certs/`. Copy `certs/ca/ca.crt` into the firmware's `include/secrets.h`. Re-run it if the server IP changes; the CA is reused.
- After editing MQTT accounts in `.env`, re-run `mqtt-passwd.sh` and `docker compose restart mqtt-broker`.
- `history-db-init` runs on every `up` and sets up CouchDB (idempotent). The backend waits for it.
- Certificates, `passwd` and `.env` are git-ignored: never commit them.

## Security

| Component | Rule |
|---|---|
| MQTT, sensor nodes | MQTTS only (TLS 1.2+, port `18883` on the host), username/password per node. ACL: a node can only publish on `vigil8/<its id>/…` and only read its own `cmd` topic |
| MQTT, services | Plain port `1883` reachable only on the Docker networks. `backend` reads all nodes and writes commands; `ia-prediction` reads telemetry only |
| CouchDB | Authentication required on every request. Published on `127.0.0.1:5984` only. User `backend` (role `writer`) is the only one allowed to write; user `ia` (role `reader`) is read-only; design docs need the admin |
| Logs | Mosquitto logs to stdout, rotated by Docker (3 × 10 MB) |

## Data flow and format

```
ESP32 ──MQTTS──► Mosquitto ──► backend ──► CouchDB (telemetry, events)
                     └───────► ia-prediction (live)      ▲
                                                         └── training export (IA_Predictions)
```

The backend is the only writer to CouchDB. It stores each MQTT message unchanged and adds `_id` (`<device_id>:<received_at>`, sorted by time) and `received_at` (server time, epoch ms).

| Topic | Direction | Content |
|---|---|---|
| `vigil8/<device_id>/telemetry` | node → server, every 2 s | sensor readings |
| `vigil8/<device_id>/event` | node → server, immediately | PIR state change |
| `vigil8/<device_id>/status` | node → server, retained | online/offline (LWT) |
| `vigil8/<device_id>/cmd` | server → node | buzzer / strobe |

Telemetry (`v: 1`):

```json
{
  "v": 1,
  "device_id": "VIG1L-8-NODE04",
  "seq": 18342,
  "uptime_ms": 36684012,
  "temp_c": 25.8,
  "hum_pct": 61.5,
  "gas_mv": 259,
  "pir": false,
  "pir_events": 0,
  "status": { "dht": "ok", "gas_warm": true, "rssi": -58 }
}
```

- `temp_c` / `hum_pct` are `null` and `status.dht` is `"error"` when the DHT22 does not answer.
- `gas_mv` is the MQ-2 analog output in mV (not calibrated, not ppm). `status.gas_warm` is `false` during the 3-minute warm-up.
- `seq` counts messages per topic (telemetry and events have their own counter): a gap means lost messages, a restart from 0 with a small `uptime_ms` means a reboot.
- `pir_events` counts motion detections since the previous telemetry message.

Event: `{"v":1,"device_id":"…","seq":18343,"uptime_ms":36685120,"type":"motion","state":true}`
Status: `{"online":true,"fw":"0.2.0","ip":"192.168.10.20"}` (the broker publishes `{"online":false}` if the node disappears)
Command: `{"buzzer":true,"strobe":true,"duration_s":8}`

Annotations (database `events`, written through the backend) mark test periods so they can be excluded from training and used to evaluate the model:

```json
{ "_id": "annotation:1791274000000", "type": "annotation", "device_id": "VIG1L-8-NODE04", "start": 1791274000000, "end": 1791274120000, "label": "gas_test", "note": "lighter, not lit, 5 cm" }
```

Graphs: the `telemetry` design doc has one view per metric (`temp_c`, `hum_pct`, `gas_mv`) keyed by `[device_id, year, month, day, hour, minute]` (UTC) with `_stats`. `group_level=6` gives per-minute stats, `5` per hour:

```
GET /telemetry/_design/telemetry/_view/gas_mv?group_level=6&startkey=["VIG1L-8-NODE04",2026,10,6]&endkey=["VIG1L-8-NODE04",2026,10,6,{}]
```

## Building the service images

Service images are built straight from the `main` branch of each service repository in the [ESPI-Workshop-Vig1l-8](https://github.com/ESPI-Workshop-Vig1l-8) organisation. Docker fetches the source during the build, so nothing is cloned into this repository and nothing is left on disk afterwards.

```bash
docker compose build            # rebuild all services from the latest main
docker compose build backend    # rebuild a single service
docker compose up -d
```

| Service         | Source repository | Image                   |
|-----------------|-------------------|-------------------------|
| `backend`       | `backend`         | `sentinel/backend:main` |
| `dashboard`     | `dashboard`       | not built yet (no Dockerfile) |
| `ia-vision`     | `IA_Vision`       | not built yet (no Dockerfile) |
| `ia-prediction` | `IA_Predictions`  | not built yet (no Dockerfile) |

When a service repository gets a `Dockerfile` at its root, uncomment the `build:` block of that service in `docker-compose.yaml`.

### Access to the private repositories

The repositories are private, so the machine running the build needs GitHub access. So far this has only been tested from a dev sandbox where GitHub credentials are injected automatically. On the server, the expected option is SSH: an SSH key with access to the organisation loaded in `ssh-agent`, the `context` written as `git@github.com:ESPI-Workshop-Vig1l-8/<repo>.git#main`, and `ssh: [default]` added under `build:`. To be confirmed when the server is set up.

The build cache stays in Docker after a build; `docker builder prune` clears it.
