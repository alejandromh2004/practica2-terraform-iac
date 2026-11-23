TF_DIR = terraform

.PHONY: help init deploy-dev deploy-pro deploy-all plan-dev plan-pro status test-alert destroy-dev destroy-pro destroy-all

help:
	@echo "Comandos disponibles:"
	@echo "  make init         - Inicializa Terraform y crea los workspaces dev y pro"
	@echo "  make deploy-dev   - Despliega el entorno DEV (2 réplicas, puerto 5000)"
	@echo "  make deploy-pro   - Despliega el entorno PRO (3 réplicas, Redis, S3, Observabilidad, puerto 5001)"
	@echo "  make deploy-all   - Despliega ambos entornos simultáneamente"
	@echo "  make status       - Muestra contenedores activos y verifica aislamiento de red"
	@echo "  make test-alert   - Detiene pro-app-3 para disparar alerta en Discord"
	@echo "  make destroy-all  - Elimina toda la infraestructura de DEV y PRO"

init:
	terraform -chdir=$(TF_DIR) init
	terraform -chdir=$(TF_DIR) workspace new dev || true
	terraform -chdir=$(TF_DIR) workspace new pro || true

plan-dev:
	terraform -chdir=$(TF_DIR) workspace select dev
	terraform -chdir=$(TF_DIR) plan -var-file=dev.tfvars

plan-pro:
	terraform -chdir=$(TF_DIR) workspace select pro
	terraform -chdir=$(TF_DIR) plan -var-file=pro.tfvars

deploy-dev:
	terraform -chdir=$(TF_DIR) workspace select dev
	terraform -chdir=$(TF_DIR) apply -var-file=dev.tfvars -auto-approve

deploy-pro:
	terraform -chdir=$(TF_DIR) workspace select pro
	terraform -chdir=$(TF_DIR) apply -var-file=pro.tfvars -auto-approve

deploy-all: deploy-dev deploy-pro

status:
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@docker network inspect pro_monitoring_net --format 'Red Interna Monitorización -> Internal: {{.Internal}} | Contenedores: {{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || true

test-alert:
	@echo "Deteniendo pro-app-3 para simular caída en producción..."
	docker stop pro-app-3
	@echo "Espera ~15-20s para recibir la alerta en Discord. Ejecuta 'make deploy-pro' para autoreparar."

destroy-dev:
	terraform -chdir=$(TF_DIR) workspace select dev
	terraform -chdir=$(TF_DIR) destroy -var-file=dev.tfvars -auto-approve

destroy-pro:
	terraform -chdir=$(TF_DIR) workspace select pro
	terraform -chdir=$(TF_DIR) destroy -var-file=pro.tfvars -auto-approve

destroy-all: destroy-dev destroy-pro
