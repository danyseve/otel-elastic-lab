.DEFAULT_GOAL := help
ANSIBLE := cd ansible && ansible-playbook --ask-vault-pass

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

infra: ## Create/update the Proxmox VMs (and the Ansible inventory)
	cd terraform && terraform init -upgrade && terraform apply

deps: ## Install Ansible collections
	cd ansible && ansible-galaxy collection install -r requirements.yml

deploy: ## Full deployment (PKI, ES, Kibana, OTel, VIP, apps)
	$(ANSIBLE) site.yml

deploy-otel: ## Only the OpenTelemetry layer
	$(ANSIBLE) site.yml --tags otel

lint: ## Run the same checks as CI
	terraform -chdir=terraform fmt -check -recursive
	cd ansible && ansible-lint
	yamllint .
	shellcheck experiments/chaos/*.sh

load: ## k6 load test against the apps (BASE_URL=...)
	k6 run experiments/k6/load.js

chaos-es: ## E1: kill an ES node (PVE_HOST=node-2 VMID=902)
	./experiments/chaos/es-node-failure.sh $(PVE_HOST) $(VMID)

chaos-gw: ## E2: OTel gateway failover
	./experiments/chaos/gateway-failover.sh

destroy: ## Destroy all VMs
	cd terraform && terraform destroy

.PHONY: help infra deps deploy deploy-otel lint load chaos-es chaos-gw destroy
