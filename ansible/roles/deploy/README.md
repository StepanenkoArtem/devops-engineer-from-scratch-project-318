# deploy

Ansible role that deploys the **bulletins** application as a Docker container on the target host: prepares the
bind-mounted volumes, pulls the requested image, starts the container, and verifies it with a post-start HTTP
health-check.

## Requirements

- Docker on the host (installed earlier in the play by the `geerlingguy.docker` role).
- The image must already be built and pushed to Docker Hub by the app repo's CI.

## Role variables

**Required — no default, must be passed at run time:**

- `image_tag` — the immutable image tag to deploy, e.g. `sha-8be5c56`. There is deliberately no default (per ADR-0001:
  never deploy `latest`); the playbook fails fast if it is undefined or empty.

**Defaults (`defaults/main.yml`, override if needed):**

- `deploy_app_uid` (`1001`) — uid the container process runs as; must match the `USER` uid in the app Dockerfile,
  otherwise the container can't write to the bind mounts.
- `deploy_app_name`, `deploy_docker_registry_repo`, `deploy_docker_container` — image and container naming;
  `deploy_docker_image` is derived from them plus `image_tag`.
- `deploy_app_base_dir` (`/opt/bulletins`), `deploy_log_path`, `deploy_tmp_path` — host paths bind-mounted into the
  container.
- `deploy_s3_bucket`, `deploy_s3_region`, `deploy_s3_endpoint` — object-storage config.
- `deploy_no_log` (`true`) — redacts the container env (secrets) from Ansible output; set `-e deploy_no_log=false` to
  debug.

**Consumed from group_vars / vault (must be defined by the play):**

- `application_port` — app port, proxied by nginx and published on `127.0.0.1`.
- `db_host`, `db_port`, `db_name`, `db_sslmode` — database connection.
- `vault_db_username`, `vault_db_password`, `vault_s3_access_key`, `vault_s3_secret_key` — secrets (Ansible Vault).

## Example

Deploy the image built for a specific commit (see the repo `Makefile`):

    make deploy IMAGE_TAG=sha-8be5c56

or invoke the playbook directly:

    ansible-playbook ansible/playbook.yml -i ansible/inventory.ini -e image_tag=sha-8be5c56
