### Hexlet tests and linter status:

[![Actions Status](https://github.com/StepanenkoArtem/devops-engineer-from-scratch-project-318/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/StepanenkoArtem/devops-engineer-from-scratch-project-318/actions)

## Server bootstrap (Ansible)

`ansible/bootstrap.yml` is a **one-shot** playbook: it takes a fresh droplet (root SSH login open on port 22) and
transitions it to a hardened state — a non-root `devops` user with key-based access, SSH moved to a custom port, root
and password authentication disabled, and UFW enabled with a default-deny inbound policy.

It is meant to run **once**, right after a droplet is created or reset. Because the playbook itself closes root@22,
re-running it will fail at connection time — that is expected, not a failure of the run. Ongoing, repeatable
configuration belongs in the main playbook (`playbook.yml`), which connects as `devops` on the configured port.

```sh
ansible-playbook ansible/bootstrap.yml -i ansible/inventory.ini
```

## Application deploy

After bootstrap, install the dependencies once (`install -r` installs both the roles and the collections from the file):

```sh
ansible-galaxy install -r ansible/requirements.yml
```

Then deploy a specific image. The playbook **requires** `image_tag` — an immutable `sha-<commit>` tag (per ADR-0001;
there is no `latest` default, and the play fails fast if the tag is missing). Deploy via the Makefile:

```sh
make deploy IMAGE_TAG=sha-<commit>
```

or call the playbook directly:

```sh
ansible-playbook ansible/playbook.yml -i ansible/inventory.ini -e image_tag=sha-<commit>
```

It connects as `devops` on the configured SSH port, sets up nginx + a Let's Encrypt TLS certificate, and deploys the app
container.

The vault password file path is set in `ansible.cfg` (`vault_password_file`), so no `--vault-password-file` flag is
needed — just make sure that file exists locally.

## Observability — metrics

Two metric sources run on the app droplet:

- **Host metrics** — `node_exporter` (role `prometheus.prometheus.node_exporter`) on port `9100`, behind basic auth
  (user `prometheus`). The port is firewalled to loopback only (`local_ports` → ufw `src 127.0.0.1`), so it is not
  reachable from the public internet — scrape it locally or, later, from a monitoring host on the private network.
- **Application metrics** — Spring Boot Actuator exposes `/actuator/prometheus` on the management port `9090`
  (`internal_actuator_port`), published by the container on `127.0.0.1:9090`. nginx reverse-proxies it on the public
  port `9091` (`public_actuator_port`) under `location /actuator/` with basic auth (`/etc/nginx/.htpasswd`, user
  `devops`). nginx access logs are emitted as JSON (`nginx_log_format` with `escape=json`) for downstream processing.

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

### Local verification (run on the droplet)

```sh
# host metrics — node_exporter (loopback + basic auth)
curl -u prometheus:$NODE_EXPORTER_PASSWORD http://localhost:9100/metrics | head

# app metrics via nginx reverse proxy (public 9091 + basic auth)
curl -u devops:$METRICS_PASSWORD http://localhost:9091/actuator/prometheus | head

# app health via nginx
curl -u devops:$METRICS_PASSWORD http://localhost:9091/actuator/health

# app metrics straight from the container (internal 9090, no auth, loopback only)
curl http://localhost:9090/actuator/prometheus | head
```

## Configuration variables

- **Group config** — `ansible/group_vars/droplets/main.yml`: `ssh_port`, `non_root_user_name`, auth toggles,
  `public_ports` / `local_ports` (ufw allow-all vs loopback-only), `domain_name`, DB settings, `application_port`,
  `internal_actuator_port` / `public_actuator_port`.
- **Role config** — `ansible/group_vars/droplets/{nginx,certbot,docker,node_exporter}.yml` (nginx also defines
  `nginx_log_format` for JSON access logs and `nginx_vhost_actuator`).
- **Secrets** — `ansible/group_vars/droplets/vault.yml` (Ansible Vault).
- **Connection** — `ansible/inventory.ini` `[droplets:vars]` (`ansible_*`); `ansible_user` and `ansible_port` reference
  the group config via `{{ non_root_user_name }}` and `{{ ssh_port }}`, so the port lives in exactly one place.
