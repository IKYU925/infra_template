# 자주 쓰는 명령 모음.  make help
ENV ?= dev
TF_DIR := terraform/envs/$(ENV)
COMPOSE := docker compose -f local/docker-compose.yml --env-file local/.env

.DEFAULT_GOAL := help
.PHONY: help local-up local-aws-up local-localstack-up local-down tf-init tf-plan tf-apply tf-fmt tf-validate ansible-deps ansible-ping ansible-run scan

help: ## 명령 목록
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

local/.env:
	cp local/.env.example local/.env

local-up: local/.env ## 로컬: postgres + app
	$(COMPOSE) up -d

local-aws-up: local/.env ## 로컬: + floci(로컬 AWS) 후 terraform/envs/local apply
	$(COMPOSE) --profile aws up -d
	terraform -chdir=terraform/envs/local init -input=false
	terraform -chdir=terraform/envs/local apply -auto-approve

local-localstack-up: local/.env ## 로컬: + LocalStack (선택)
	$(COMPOSE) --profile localstack up -d

local-down: ## 로컬 환경 종료 (볼륨 유지)
	$(COMPOSE) --profile aws --profile localstack --profile ansible-lab down

tf-init: ## terraform init (ENV=dev|prod)
	terraform -chdir=$(TF_DIR) init -backend-config=backend.hcl

tf-plan: ## terraform plan (ENV=dev|prod)
	terraform -chdir=$(TF_DIR) plan -out=tfplan

tf-apply: ## 저장된 plan 적용 (ENV=dev|prod)
	terraform -chdir=$(TF_DIR) apply tfplan

tf-fmt: ## terraform fmt
	terraform fmt -recursive terraform

tf-validate: ## 모든 루트 validate (backend 없이)
	@for d in bootstrap envs/local envs/dev envs/prod; do echo "== $$d"; terraform -chdir=terraform/$$d init -backend=false -input=false >/dev/null && terraform -chdir=terraform/$$d validate || exit 1; done

ansible-deps: ## Ansible 롤/컬렉션 설치
	cd ansible && ansible-galaxy role install -r requirements.yml -p .galaxy/roles && ansible-galaxy collection install -r requirements.yml -p .galaxy/collections

ansible-ping: ## 인벤토리 접속 확인 (ENV=local|dev|prod)
	cd ansible && ansible -i inventories/$(ENV) all -m ansible.builtin.ping

ansible-run: ## site.yml 실행 (ENV=local|dev|prod)
	cd ansible && ansible-playbook -i inventories/$(ENV) playbooks/site.yml --diff

scan: ## Trivy + Checkov 로컬 실행 (Docker 필요)
	docker run --rm -v $(PWD):/src -w /src aquasec/trivy:0.76.1 fs --config trivy.yaml .
	docker run --rm -v $(PWD):/src -w /src bridgecrew/checkov:3.4.1 --config-file .checkov.yaml
