.DEFAULT_GOAL := help

help: ## Show this help 
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

droplet: ## Bootstrap brand new single droplet
	@test -n "$(HOST)" || { echo "usage: make droplet HOST=<host>"; exit 1; }
	ansible-playbook ansible/droplets.yml -i ansible/inventory.ini "--limit=$(HOST)"

IMAGE_TAG_ARG =$(if $(IMAGE_TAG),-e "image_tag=$(IMAGE_TAG)")

deploy: ## Deploy everything: application first, monitoring only if that succeeded
	$(MAKE) application
	$(MAKE) monitoring

application: ## Deploy application (pinned version, or IMAGE_TAG=sha-<commit>)
	ansible-playbook ansible/application.yml -i ansible/inventory.ini $(IMAGE_TAG_ARG) --limit=application

application-check: ## Dry-run application deploy (--check --diff)
	ansible-playbook ansible/application.yml -i ansible/inventory.ini $(IMAGE_TAG_ARG) --limit=application --check --diff

monitoring: ## Deploy monitoring server
	ansible-playbook ansible/monitoring.yml -i ansible/inventory.ini

monitoring-check: ## Dry-run monitoring deploy (--check --diff)
	ansible-playbook ansible/monitoring.yml -i ansible/inventory.ini --check --diff

requirements: ## Install python dependencies and Ansible collections/roles
	python3 -m pip install -r requirements.txt && ansible-galaxy install -r ansible/requirements.yml

lint: ## Run ansible-lint (static checks, no hosts contacted)
	ansible-lint

test: ## Run the nginx_exporter role in a throwaway container with Molecule (needs Docker)
	cd ansible/roles/nginx_exporter && molecule test

smoke: ## Check the live system: public endpoints, Prometheus, Loki and every scrape target
	ansible-playbook ansible/smoke.yml -i ansible/inventory.ini


.PHONY: help droplet deploy application application-check monitoring monitoring-check requirements lint test smoke
