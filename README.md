### Hexlet tests and linter status:

[![Actions Status](https://github.com/StepanenkoArtem/devops-engineer-from-scratch-project-318/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/StepanenkoArtem/devops-engineer-from-scratch-project-318/actions)

## Overview

Two DigitalOcean droplets in a shared VPC:

| Host         | Role                    | Public IP         | VPC (private) IP | User     |
| ------------ | ----------------------- | ----------------- | ---------------- | -------- |
| `hexlet-app` | application + nginx/TLS | `165.232.125.175` | `10.114.0.2`     | `devops` |
| `monitoring` | Prometheus (+ stack)    | `165.227.174.50`  | `10.114.0.3`     | `admin`  |

All host-to-host traffic (metrics scraping) goes over the **private VPC network** — nothing about observability is
exposed to the public internet. SSH is on a custom port, key-based, root login disabled (see bootstrap).

The application is served over HTTPS at **https://bulletins.artem.diy** (nginx + Let's Encrypt on `hexlet-app`).

## Playbooks & Make targets

| Playbook          | Runs on       | Make target                        | Purpose                                |
| ----------------- | ------------- | ---------------------------------- | -------------------------------------- |
| `droplets.yml`    | any droplet   | `make droplet HOST=<host>`         | one-shot bootstrap of a fresh droplet  |
| `application.yml` | `application` | `make application IMAGE_TAG=sha-…` | deploy the app (nginx, TLS, container) |
| `monitoring.yml`  | `monitoring`  | `make monitoring`                  | deploy Prometheus + node_exporter      |

Install dependencies (Ansible roles + collections + Python deps) once:

```sh
make requirements
```

## Server bootstrap (Ansible)

`ansible/droplets.yml` is a **one-shot** playbook: it takes a fresh droplet (root SSH login open on port 22) and
transitions it to a hardened state — a non-root user with key-based access, SSH moved to a custom port, root and
password authentication disabled, and UFW enabled with a default-deny inbound policy.

Run it **once** per droplet, right after creation/reset, targeting a single host:

```sh
make droplet HOST=application    # or: HOST=monitoring
```

Because the playbook itself closes root@22, re-running it will fail at connection time — that is expected, not a bug.
Ongoing, repeatable configuration lives in the per-role playbooks (`application.yml`, `monitoring.yml`), which connect
as the non-root user on the configured port.

## Application deploy

Deploy a specific image. The play **requires** `image_tag` — an immutable `sha-<commit>` tag (per ADR-0001; there is no
`latest` default, and the play fails fast if the tag is missing):

```sh
make application IMAGE_TAG=sha-<commit>
```

It sets up nginx + a Let's Encrypt TLS certificate and deploys the app container. The vault password file path is set in
`ansible.cfg` (`vault_password_file`), so no `--vault-password-file` flag is needed — just make sure that file exists
locally.

## Monitoring — Prometheus

`ansible/monitoring.yml` deploys Prometheus on the `monitoring` droplet as a Docker container:

- own Docker network `monitoring` (for the future stack — Grafana/Alertmanager);
- **config** as a host bind-mount `/etc/prometheus/prometheus.yml` (rendered from
  `templates/prometheus/prometheus.yml.j2` and **validated with `promtool`** before it is applied — a bad config never
  reaches the running server);
- **data** as a named volume `prometheus-data` → `/prometheus` (survives container recreation);
- published on **`127.0.0.1:9090` only** — Prometheus is internal. It is not exposed publicly; the public-facing UI will
  be Grafana later. On config change the container is reloaded via `SIGHUP`.

### Scrape targets

All targets are scraped over the **private VPC network**; none is publicly reachable.

| Job           | Target(s)                              | Path                   | Notes                                |
| ------------- | -------------------------------------- | ---------------------- | ------------------------------------ |
| `node`        | `10.114.0.2:9100` (`role=application`) | `/metrics`             | node_exporter on the app host        |
|               | `10.114.0.3:9100` (`role=monitoring`)  | `/metrics`             | node_exporter on the monitoring host |
| `application` | `10.114.0.2:9090`                      | `/actuator/prometheus` | Spring Boot Actuator over VPC        |

### Access & verification (`up == 1`)

Prometheus listens on loopback only, so reach it through an **SSH tunnel** from your machine:

```sh
ssh -L 9090:localhost:9090 -i ~/.ssh/monitoring -p 23332 admin@165.227.174.50
# then open http://localhost:9090/graph  (or /targets)
```

Verify every target is healthy (`up == 1`) — via the tunnel, or directly on the monitoring host:

```sh
# expect one line per target, all up=1
curl -s 'http://localhost:9090/api/v1/query?query=up' \
  | jq -r '.data.result[] | "\(.metric.job)\t\(.metric.instance)\tup=\(.value[1])"'

# count of healthy targets (expect 3)
curl -s 'http://localhost:9090/api/v1/query?query=count(up==1)' | jq -r '.data.result[0].value[1]'
```

## Observability — metrics

Two metric sources are collected:

- **Host metrics** — `node_exporter` (role `prometheus.prometheus.node_exporter`) on port `9100`, running on **both**
  hosts. It listens on all interfaces but UFW allows `9100` only from the monitoring node over the VPC — not reachable
  from the public internet. No basic auth: access is controlled at the network layer (VPC + firewall).
- **Application metrics** — Spring Boot Actuator exposes `/actuator/prometheus` on management port `9090`, published by
  the container on the app host's **private** address `10.114.0.2:9090` (VPC only, not public). nginx access logs are
  emitted as JSON (`nginx_log_format` with `escape=json`) for downstream processing.

### Mandatory host metrics (node_exporter)

| Area            | Metric                                                                  | Meaning                             |
| --------------- | ----------------------------------------------------------------------- | ----------------------------------- |
| CPU load        | `node_load1` / `node_load5` / `node_load15`                             | load average over 1 / 5 / 15 min    |
| Memory          | `node_memory_MemAvailable_bytes`, `node_memory_MemTotal_bytes`          | available / total RAM               |
| Disk            | `node_filesystem_avail_bytes`, `node_filesystem_size_bytes`             | free / total space per filesystem   |
| Network         | `node_network_receive_bytes_total`, `node_network_transmit_bytes_total` | bytes received / sent per interface |
| Processes       | `node_procs_running`, `node_procs_blocked`                              | runnable / blocked processes        |
| System services | `node_systemd_unit_state`                                               | state of each systemd unit          |

### Application metrics (Actuator / Micrometer)

| Area              | Metric                                                    | Meaning                                    |
| ----------------- | --------------------------------------------------------- | ------------------------------------------ |
| Uptime            | `process_uptime_seconds`                                  | seconds since the app started              |
| HTTP requests     | `http_server_requests_seconds_count` / `_sum` / `_bucket` | request count, total time, latency buckets |
| JVM memory        | `jvm_memory_used_bytes`                                   | JVM heap / non-heap usage                  |
| JVM GC            | `jvm_gc_pause_seconds_count` / `_sum`                     | garbage-collection pauses                  |
| DB pool           | `hikaricp_connections_active`                             | active DB connections                      |
| System (app view) | `system_cpu_usage`, `system_load_average_1m`              | host CPU / load as seen by the app         |

All application metrics carry `application` and `environment` labels (from `management.metrics.tags`).

## Configuration variables

Variables are split by scope across `ansible/group_vars/`:

- **Shared (both hosts)** — `group_vars/droplets/`: bootstrap (`ssh_port`, `non_root_user_name`, auth toggles), private
  addresses (`application_private_address`, `monitoring_private_address`), metric ports (`actuator_port`,
  `node_exporter.yml`), `docker.yml`, `accept-new` SSH arg, and secrets in `vault.yml` (Ansible Vault).
- **App-only** — `group_vars/application/`: `nginx.yml`, `certbot.yml`, `domain_name`, DB settings, `public_ports`,
  `monitoring_ports` (ufw: what the monitoring node may reach over the VPC).
- **Monitoring-only** — `group_vars/monitoring/`: connection key/user, `monitoring_network`,
  `prometheus_config_directory`.
- **Connection** — `ansible/inventory.ini`: parent group `droplets` with children `application` / `monitoring`; shared
  `ansible_*` connection vars reference the group config (`{{ non_root_user_name }}`, `{{ ssh_port }}`).
