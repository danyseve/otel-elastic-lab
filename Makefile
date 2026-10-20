.DEFAULT_GOAL := help
ANSIBLE := cd ansible && ansible-playbook --ask-vault-pass
export KUBECONFIG := $(CURDIR)/ansible/.kube/config

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

infra: ## Create/update the 3 node VMs (and the Ansible inventory)
	cd terraform && terraform init -upgrade && terraform apply

deps: ## Install Ansible collections
	cd ansible && ansible-galaxy collection install -r requirements.yml

cluster: ## OS baseline + k3s HA cluster (writes ansible/.kube/config)
	$(ANSIBLE) site.yml --tags common,k3s

platform: ## cert-manager, MetalLB, ECK, Elasticsearch, Kibana, OTel (Helmfile)
	cd k8s && helmfile apply

agents: ## OTel agent + instrumentation on the app hosts outside the cluster
	$(ANSIBLE) site.yml --tags apps

status: ## Elasticsearch / Kibana health as reported by ECK
	kubectl -n observability get elasticsearch,kibana,opentelemetrycollectors

elastic-password: ## Print the 'elastic' superuser password
	@kubectl -n observability get secret lab-es-elastic-user -o go-template='{{.data.elastic | base64decode}}{{"\n"}}'

lint: ## Run the same checks as CI
	terraform -chdir=terraform fmt -check -recursive
	cd ansible && ansible-lint
	yamllint .
	shellcheck experiments/chaos/*.sh
	helm lint k8s/charts/lab-platform -f k8s/values/lab.yaml.example

load: ## k6 load test against the apps (BASE_URL=...)
	k6 run experiments/k6/load.js

chaos-node: ## E1: hard-stop a node VM (HV_HOST=node-2 VMID=902)
	./experiments/chaos/es-node-failure.sh $(HV_HOST) $(VMID)

chaos-gw: ## E2: kill a gateway pod (GATEWAY_IP=... CA_CERT=...)
	./experiments/chaos/gateway-failover.sh

destroy: ## Destroy all VMs
	cd terraform && terraform destroy

.PHONY: help infra deps cluster platform agents status elastic-password lint load chaos-node chaos-gw destroy
