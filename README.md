# Sentinel-X — infra

Docker Compose stack for the Sentinel-X "PC Serveur Local": Mosquitto (MQTT broker), CouchDB (telemetry history), the Go backend, the dashboard and the AI services.

## Setup

```bash
cp .env.example .env   # then fill in the values
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
| `frontend`      | `dashboard`       | not built yet (no Dockerfile) |
| `ia-vision`     | `IA_Vision`       | not built yet (no Dockerfile) |
| `ia-prediction` | `IA_Predictions`  | not built yet (no Dockerfile) |

When a service repository gets a `Dockerfile` at its root, uncomment the `build:` block of that service in `docker-compose.yaml`.

### Access to the private repositories

The repositories are private, so the machine running the build needs GitHub access. So far this has only been tested from a dev sandbox where GitHub credentials are injected automatically. On the server, the expected option is SSH: an SSH key with access to the organisation loaded in `ssh-agent`, the `context` written as `git@github.com:ESPI-Workshop-Vig1l-8/<repo>.git#main`, and `ssh: [default]` added under `build:`. To be confirmed when the server is set up.

The build cache stays in Docker after a build; `docker builder prune` clears it.
