# Homelab Setup Makefile
# Requires: .env file with MACHINE_NAME, BW_CLIENTID, BW_CLIENTSECRET, BW_PASSWORD

.PHONY: help secrets infra deploy

help:
	@echo "Usage:"
	@echo "  make secrets  - Sync secrets from Bitwarden to K8s"
	@echo "  make infra    - Run infrastructure setup (K3s, etc.)"
	@echo "  make deploy   - Apply Kubernetes manifests"
	@echo ""
	@echo "Requires .env file with: MACHINE_NAME, BW_CLIENTID, BW_CLIENTSECRET, BW_PASSWORD"

secrets:
	@test -f .env || (echo "Error: .env file not found" && exit 1)
	@set -a && source .env && set +a && \
		ansible-playbook ansible/playbook.yml --tags secrets -i localhost,

infra:
	@test -f .env || (echo "Error: .env file not found" && exit 1)
	@set -a && source .env && set +a && \
		echo "[homelab]" > /tmp/homelab-inventory && \
		echo "$${MACHINE_NAME} ansible_user=root" >> /tmp/homelab-inventory && \
		ansible-playbook ansible/playbook.yml -i /tmp/homelab-inventory --tags infra

deploy:
	kubectl apply -k kubernetes/
