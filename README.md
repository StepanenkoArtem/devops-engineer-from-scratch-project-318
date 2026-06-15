### Hexlet tests and linter status:
[![Actions Status](https://github.com/StepanenkoArtem/devops-engineer-from-scratch-project-318/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/StepanenkoArtem/devops-engineer-from-scratch-project-318/actions)

## Server bootstrap (Ansible)

`ansible/bootstrap.yml` is a **one-shot** playbook: it takes a fresh droplet
(root SSH login open on port 22) and transitions it to a hardened state —
a non-root `devops` user with key-based access, SSH moved to a custom port,
root and password authentication disabled, and UFW enabled with a
default-deny inbound policy.

It is meant to run **once**, right after a droplet is created or reset.
Because the playbook itself closes root@22, re-running it will fail at
connection time — that is expected, not a failure of the run. Ongoing,
repeatable configuration belongs in the main playbook (`playbook.yml`),
which connects as `devops` on the configured port.

```sh
ansible-playbook ansible/bootstrap.yml -i ansible/bootstrap.ini
```

Variables (host/group): see `ansible/group_vars/droplets.yml`
(`ssh_port`, `non_root_user_name`, auth toggles, connection key path).