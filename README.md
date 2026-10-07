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
- Dashboard: `http://localhost:10443`, **on the server PC only** (published on `127.0.0.1`). To open it from another machine, change the `ports` line of the `dashboard` service (`10443:8080`) or use an SSH tunnel (`ssh -L 10443:127.0.0.1:10443 <server>`). The access key is `API_OPERATOR_TOKEN` (full access) or `API_SERVICE_TOKEN` (read-only). The AI services use `API_SERVICE_TOKEN` to `POST /api/v1/alerts` on `http://backend:5000` (API reference in the `backend` README).
- Certificates, `passwd` and `.env` are git-ignored: never commit them.
- Only two ports are published: MQTTS `18883` for the nodes and the dashboard on `127.0.0.1:10443`. Training data comes from the dashboard's **Export CSV** button (backend `GET /api/v1/devices/{id}/export.csv`), or from inside the stack (`docker compose run --rm ia-prediction python entrainement.py --source couchdb`). CouchDB admin, when needed: `docker compose exec history-db curl -s -u "admin:<password>" http://localhost:5984/_all_dbs`.

## Security

| Component | Rule |
|---|---|
| MQTT, sensor nodes | MQTTS only (TLS 1.2+, port `18883` on the host), username/password per node. ACL: a node can only publish on `vigil8/<its id>/…` and only read its own `cmd` topic |
| MQTT, services | Plain port `1883` reachable only on the Docker networks. Only `backend` has a service account: it reads all nodes and writes commands. The AI services have no broker access |
| CouchDB | Authentication required on every request. Not published on the host: only reachable on the Docker networks of `backend` and `ia-prediction`. User `backend` (role `writer`) is the only one allowed to write; user `ia` (role `reader`) is read-only and is how `ia-prediction` gets the live readings; design docs need the admin |
| HTTP | Only the dashboard's nginx is published, on `127.0.0.1:10443` (not reachable from the network); it serves the app and proxies `/api` and `/ws` to the backend, which is not published. Every API call needs a token: operator (dashboard, commands) or service (AI: read + alerts) |
| Ports | Non-standard host ports (MQTTS `18883` instead of 8883, dashboard `10443`): automated attacks (bots, quick scans, worms) target the default ports of common services, so this keeps them out of reach and the logs quieter. It complements TLS, authentication and ACLs; it does not replace them, since a full scan (`nmap -p-`) still finds the ports |
| Logs | Mosquitto logs to stdout, rotated by Docker (3 × 10 MB) |

## Data flow and format

```
ESP32 ──MQTTS──► Mosquitto ──► backend ──► CouchDB (telemetry, events)
                                  ▲                │ read-only (_changes feed + training export)
                                  │                ▼
                                  └── alerts ── ia-prediction
```

The backend is the only writer to CouchDB. It stores each MQTT message unchanged and adds `_id` (`<device_id>:<received_at>`, sorted by time) and `received_at` (server time, epoch ms).

| Topic | Direction | Content |
|---|---|---|
| `vigil8/<device_id>/telemetry` | node → server, every 2 s | sensor readings |
| `vigil8/<device_id>/event` | node → server, immediately | PIR state change |
| `vigil8/<device_id>/status` | node → server, retained | online/offline (LWT) |
| `vigil8/<device_id>/cmd` | server → node | alert LED (strobe) |

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
  "status": { "dht": "ok", "gas_warm": true, "env_warn": false, "rssi": -58 }
}
```

- `temp_c` / `hum_pct` are `null` and `status.dht` is `"error"` when the DHT22 does not answer.
- `gas_mv` is the MQ-2 analog output in mV (not calibrated, not ppm). `status.gas_warm` is `false` during the 3-minute warm-up.
- `seq` counts messages per topic (telemetry and events have their own counter): a gap means lost messages, a restart from 0 with a small `uptime_ms` means a reboot.
- `pir_events` counts motion detections since the previous telemetry message.
- `status.env_warn` is `true` while the node's local fixed ceiling (temperature or gas) is exceeded; it only drives the node's warning LED, anomaly detection is done by the AI.

Event: `{"v":1,"device_id":"…","seq":18343,"uptime_ms":36685120,"type":"motion","state":true}`
Status: `{"online":true,"fw":"0.2.0","ip":"192.168.10.5"}` (the broker publishes `{"online":false}` if the node disappears)
Command: `{"strobe":true,"duration_s":8}` makes the node's environment LED blink (server alert, 1–60 s)

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
| `dashboard`     | `dashboard`       | `sentinel/dashboard:main` |
| `ia-prediction` | `IA_Predictions`  | `sentinel/ia-prediction:main` |

## AI services

- **ia-prediction** (container): live Isolation Forest on the readings stored in CouchDB (`_changes` feed of `telemetry`, read-only `ia` user: only data validated by the backend), sends `warning` / `confirmed` alerts to the backend. The model lives on the `prediction-models` volume; to retrain on the real data stored in CouchDB:
  ```bash
  docker compose run --rm ia-prediction python entrainement.py --source couchdb
  docker compose restart ia-prediction
  ```
  Until then, the model shipped in the repository is used (trained on simulated data).
- **ia-vision** (container, **Linux only**): YOLO intrusion detection on the USB webcam passed with `devices: /dev/video0`, `warning` / `confirmed` alerts to the backend, MJPEG stream shown by the dashboard under `/vision/` (protected by the access key). The YOLO weights are downloaded when the image is built, so it runs offline on the hotspot. Set `VIDEO_GID` to the gid of the host's `video` group (`getent group video`) and `VISION_CAMERA` if the webcam is not `/dev/video0` (`v4l2-ctl --list-devices`).
  **Windows/macOS:** Docker Desktop cannot access USB webcams. Start the stack without this service (`docker compose up -d --scale ia-vision=0`), run IA_Vision on the host (`python main.py`, see its README) and set `VISION_UPSTREAM=http://<host IP>:8000` (e.g. `http://192.168.10.1:8000`).

### Repository access

For this school project, the organisation's repositories are **public**, so that `docker compose build` can fetch the sources without credentials. In a real deployment they would stay **private** and the build machine would authenticate to GitHub: an SSH key (or deploy key) with read-only access loaded in `ssh-agent`, contexts written as `git@github.com:ESPI-Workshop-Vig1l-8/<repo>.git#main`, and `ssh: [default]` under `build:`.

No secret is stored in the repositories: credentials live in `.env`, `config/mosquitto/passwd`, `certs/` and the firmware's `include/secrets.h`, all git-ignored.

The build needs Internet access: run `docker compose build` **before** switching the PC's Wi-Fi to the table hotspot (the card can't be a hotspot and connected to another network at the same time). `docker compose up -d` then runs offline.

The build cache stays in Docker after a build; `docker builder prune` clears it.
