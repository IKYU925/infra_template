# 자주 쓰는 명령 모음.  make help
ENV ?= dev
REGION ?= ap-northeast-2
TF_DIR := terraform/envs/$(ENV)
COMPOSE := docker compose -f local/docker-compose.yml --env-file local/.env
VAGRANT_DIR := local/vagrant
LOCAL_KUBECONFIG := $(CURDIR)/$(VAGRANT_DIR)/.kube/config
LOCAL_KUBECTL := KUBECONFIG=$(LOCAL_KUBECONFIG) kubectl
LOCAL_HELM := KUBECONFIG=$(LOCAL_KUBECONFIG) helm
ARGOCD_CHART_VERSION := 10.14.0

.DEFAULT_GOAL := help
.PHONY: help k3s-up k3s-halt k3s-destroy local-secret local-deploy local-image-import \
	local-up local-aws-up local-localstack-up local-down \
	tf-init tf-plan tf-apply tf-fmt tf-validate ansible-deps ansible-lint k8s-lint argocd-bootstrap scan

help: ## 명령 목록
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

local/.env:
	cp local/.env.example local/.env

# ---------------------------------------------------------------- 로컬 k3s (Vagrant)
k3s-up: ## 로컬 k3s 클러스터 생성/시작 (컨트롤 플레인 1 + 워커 2)
	cd $(VAGRANT_DIR) && vagrant up
	@echo "kubectl 을 쓰려면: export KUBECONFIG=$(LOCAL_KUBECONFIG)"
	$(LOCAL_KUBECTL) get nodes -o wide

k3s-halt: ## 로컬 k3s VM 끄기 (디스크 유지)
	cd $(VAGRANT_DIR) && vagrant halt

k3s-destroy: ## 로컬 k3s VM 삭제
	cd $(VAGRANT_DIR) && vagrant destroy -f

local-secret: local/.env ## 로컬 k3s 에 DB Secret 생성 (local/.env 의 POSTGRES_PASSWORD)
	$(LOCAL_KUBECTL) create namespace app --dry-run=client -o yaml | $(LOCAL_KUBECTL) apply -f -
	set -a && . ./local/.env && set +a && \
	$(LOCAL_KUBECTL) -n app create secret generic app-db \
	  --from-literal=POSTGRES_PASSWORD="$$POSTGRES_PASSWORD" \
	  --from-literal=DATABASE_URL="postgresql://app:$$POSTGRES_PASSWORD@postgresql:5432/app" \
	  --dry-run=client -o yaml | $(LOCAL_KUBECTL) apply -f -

local-deploy: local-secret ## 로컬 k3s 에 앱 배포 (Helm) -> http://192.168.56.10
	$(LOCAL_HELM) upgrade --install app deploy/charts/app -n app -f deploy/charts/app/values-local.yaml --wait

local-image-import: ## 노트북에서 빌드한 이미지를 켜진 VM 모두에 넣기 (IMAGE=myapp:dev)
	@test -n "$(IMAGE)" || (echo "IMAGE=<이미지:태그> 를 지정하세요" && exit 1)
	docker save $(IMAGE) -o $(VAGRANT_DIR)/.image.tar
	cd $(VAGRANT_DIR) && for n in $$(vagrant status --machine-readable | awk -F, '$$3=="state" && $$4=="running" {print $$2}'); do \
	  echo "== $$n"; vagrant ssh $$n -c "sudo k3s ctr images import /vagrant/$(VAGRANT_DIR)/.image.tar" || exit 1; done

# ---------------------------------------------------------------- 로컬 Compose (앱만 빠르게 실행, 선택)
local-up: local/.env ## 로컬 Compose: postgres + app
	$(COMPOSE) up -d

local-aws-up: local/.env ## 로컬 Compose: + floci(로컬 AWS) 후 terraform/envs/local apply
	$(COMPOSE) --profile aws up -d
	terraform -chdir=terraform/envs/local init -input=false
	terraform -chdir=terraform/envs/local apply -auto-approve

local-localstack-up: local/.env ## 로컬 Compose: + LocalStack (선택)
	$(COMPOSE) --profile localstack up -d

local-down: ## 로컬 Compose 종료 (볼륨 유지)
	$(COMPOSE) --profile aws --profile localstack down

# ---------------------------------------------------------------- Terraform (dev/prod)
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

# ---------------------------------------------------------------- Ansible (로컬 VM)
ansible-deps: ## Ansible 컬렉션 설치
	cd ansible && ansible-galaxy collection install -r requirements.yml -p .galaxy/collections

ansible-lint: ## syntax-check + ansible-lint
	cd ansible && ansible-playbook -i inventories/local playbooks/site.yml --syntax-check && ansible-lint

# ---------------------------------------------------------------- Kubernetes
k8s-lint: ## Helm 차트 lint + 렌더링 확인 (local/dev/prod)
	@for e in local dev prod; do echo "== $$e"; helm lint deploy/charts/app -f deploy/charts/app/values-$$e.yaml && helm template app deploy/charts/app -n app -f deploy/charts/app/values-$$e.yaml >/dev/null || exit 1; done

argocd-bootstrap: ## EKS 에 Argo CD 설치 + app-of-apps 등록 (ENV=dev|prod, 클러스터당 1회)
	aws eks update-kubeconfig --region $(REGION) --name $$(terraform -chdir=$(TF_DIR) output -raw cluster_name)
	helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version $(ARGOCD_CHART_VERSION) \
	  -n argocd --create-namespace -f deploy/argocd/values.yaml --wait
	kubectl apply -f deploy/argocd/$(ENV)-root.yaml

scan: ## Trivy + Checkov 로컬 실행 (Docker 필요)
	docker run --rm -v $(PWD):/src -w /src aquasec/trivy:0.76.1 fs --config trivy.yaml .
	docker run --rm -v $(PWD):/src -w /src bridgecrew/checkov:3.4.1 --config-file .checkov.yaml
