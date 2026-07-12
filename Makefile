.DEFAULT_GOAL := help

help: ## Show this help 
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

droplet: ## Bootstrap brand new droplet
	ansible-playbook  ansible/bootstrap.yml -i ansible/inventory.ini

deploy: ## Deploy application with given SHA
	@test -n "$(IMAGE_TAG)" || { echo "usage: make deploy IMAGE_TAG=sha-<commit>"; exit 1; }
	ansible-playbook ansible/playbook.yml -i ansible/inventory.ini -e "image_tag=$(IMAGE_TAG)"

requirements: ## Install python dependencies and Ansible collections/roles 
	python -m pip install -r requirements.txt && ansible-galaxy install -r ansible/requirements.yml


.PHONY: help droplet deploy requirements
