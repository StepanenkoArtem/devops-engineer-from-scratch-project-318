.DEFAULT_GOAL := help

help: ## Show this help 
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

droplet: ## Bootstrap brand new single droplet
	@test -n "$(HOST)" || { echo "usage: make droplet HOST=<host>"; exit 1; }
	ansible-playbook ansible/droplets.yml -i ansible/inventory.ini "--limit=$(HOST)"

application: ## Deploy application with given SHA
	@test -n "$(IMAGE_TAG)" || { echo "usage: make application IMAGE_TAG=sha-<commit>"; exit 1; }
	ansible-playbook ansible/application.yml -i ansible/inventory.ini -e "image_tag=$(IMAGE_TAG)" --limit=application

prometheus: ## Deploy Prometheus server 
	ansible-playbook ansible/prometheus.yml -i ansible/inventory.ini --limit=prometheus

requirements: ## Install python dependencies and Ansible collections/roles 
	python3 -m pip install -r requirements.txt && ansible-galaxy install -r ansible/requirements.yml


.PHONY: help droplet application prometheus requirements
