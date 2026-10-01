# deploy

Deploys the Bulletins application as a Docker container: prepares the bind-mounted directories, pulls the image, starts
the container and waits for the Actuator health endpoint.

## Requirements

- Docker on the host (the play installs it with `geerlingguy.docker` first).
- The image is already built and pushed to Docker Hub by the application repository's CI.

## Variables

Inputs with no default, set in the inventory:

| Variable                                                     | Where it is set                             |
| ------------------------------------------------------------ | ------------------------------------------- |
| `image_tag`                                                  | `ansible/group_vars/application/deploy.yml` |
| `deploy_s3_bucket`, `deploy_s3_region`, `deploy_s3_endpoint` | `ansible/group_vars/application/deploy.yml` |
| `db_host`, `db_port`, `db_name`, `db_sslmode`                | `ansible/group_vars/application/main.yml`   |
| `vault_db_username`, `vault_db_password`                     | `ansible/group_vars/application/vault.yml`  |
| `vault_s3_access_key`, `vault_s3_secret_key`                 | `ansible/group_vars/application/vault.yml`  |
| `app_container_name`, `private_address`, `service_ports`     | inventory group and host variables          |

`image_tag` must be an immutable `sha-<commit>` tag; `application.yml` rejects anything else before touching the host.

Defaults in `defaults/main.yml`:

- `deploy_app_uid` (`1001`) must match the `USER` uid in the application Dockerfile, otherwise the container cannot
  write to the bind mounts.
- `deploy_http_container_port` (`8080`) and `deploy_actuator_container_port` (`9090`) are passed to the application as
  `SERVER_PORT` and `MANAGEMENT_SERVER_PORT`.
- `deploy_web_log_level` (`INFO`).

The container environment holds secrets, so its task runs with `no_log`. Pass `-e no_log=false` to debug.

## Example

    make application                        # the version pinned in the inventory
    make application IMAGE_TAG=sha-8be5c56  # another version for this run
