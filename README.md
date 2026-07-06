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

## Configuration variables

- **Group config** — `ansible/group_vars/droplets/main.yml`: `ssh_port`, `non_root_user_name`, auth toggles, `ports`,
  `domain_name`, DB settings, `application_port`.
- **Role config** — `ansible/group_vars/droplets/{nginx,certbot,docker}.yml`.
- **Secrets** — `ansible/group_vars/droplets/vault.yml` (Ansible Vault).
- **Connection** — `ansible/inventory.ini` `[droplets:vars]` (`ansible_*`); `ansible_user` and `ansible_port` reference
  the group config via `{{ non_root_user_name }}` and `{{ ssh_port }}`, so the port lives in exactly one place.
