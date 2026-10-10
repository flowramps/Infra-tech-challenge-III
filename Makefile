SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

ENV          ?= local
TF_DIR       := terraform
TF_VARS      := environments/$(ENV)/terraform.tfvars
TF_BACKEND   := environments/$(ENV)/backend.hcl
COMPOSE      := docker compose -f bootstrap/docker-compose.yml
# Argo CD follows the checked-out branch (it must be pushed to GitHub).
GITOPS_REVISION ?= $(shell git rev-parse --abbrev-ref HEAD)
TF_APP_VARS  := -var-file=$(TF_VARS) -var gitops_revision=$(GITOPS_REVISION)

# Remote state backend (bootstrap/docker-compose.yml). Local-only credentials.
S3_ENDPOINT  := http://127.0.0.1:7070
export AWS_ACCESS_KEY_ID     := $(or $(TFSTATE_ACCESS_KEY),tfstate-local)
export AWS_SECRET_ACCESS_KEY := $(or $(TFSTATE_SECRET_KEY),tfstate-local-secret)
export TFSTATE_ACCESS_KEY    := $(AWS_ACCESS_KEY_ID)
export TFSTATE_SECRET_KEY    := $(AWS_SECRET_ACCESS_KEY)
# Never let real cloud credentials from the shell reach the local backend.
unexport AWS_SESSION_TOKEN AWS_PROFILE AWS_DEFAULT_PROFILE

# The S3 backend renamed its custom endpoint options in Terraform 1.6.
TF_VERSION := $(shell terraform version -json 2>/dev/null | sed -n 's/.*"terraform_version": *"\([0-9.]*\)".*/\1/p')
ifeq ($(shell printf '%s\n' 1.6.0 "$(TF_VERSION)" | sort -V | head -1),1.6.0)
  TF_S3_ENDPOINT := -backend-config='endpoints={s3="$(S3_ENDPOINT)"}' -backend-config=use_path_style=true -backend-config=skip_requesting_account_id=true
else
  TF_S3_ENDPOINT := -backend-config=endpoint=$(S3_ENDPOINT) -backend-config=force_path_style=true
endif

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: preflight state init apply info ## Create everything (state backend, cluster, observability, mesh, app)

.PHONY: down
down: destroy ## Destroy the cluster (keeps the state backend)

.PHONY: preflight
preflight: ## Check local prerequisites
	@for bin in docker kind terraform kubectl helm; do \
	  command -v $$bin >/dev/null || { echo "missing required tool: $$bin" >&2; exit 1; }; \
	done
	@if [ "$$(uname)" = Linux ] && [ "$$(sysctl -n fs.inotify.max_user_instances)" -lt 512 ]; then \
	  echo "fs.inotify limits are too low for a multi-node kind cluster (workers fail to join). Run:" >&2; \
	  echo "  sudo sysctl -w fs.inotify.max_user_watches=524288 fs.inotify.max_user_instances=512" >&2; \
	  exit 1; \
	fi

.PHONY: state
state: ## Start the S3-compatible state backend and create the bucket
	$(COMPOSE) up -d s3
	$(COMPOSE) run --rm create-bucket

.PHONY: init
init: ## terraform init against the remote state
	terraform -chdir=$(TF_DIR) init -reconfigure -backend-config=$(TF_BACKEND) $(TF_S3_ENDPOINT)

.PHONY: plan
plan: ## terraform plan
	terraform -chdir=$(TF_DIR) plan $(TF_APP_VARS)

.PHONY: apply
apply: ## terraform apply
	terraform -chdir=$(TF_DIR) apply $(TF_APP_VARS) -auto-approve

.PHONY: destroy
destroy: ## terraform destroy
	@# No refresh: when the cluster config changed, a refresh would plan its
	@# replacement and leave the Kubernetes providers without an endpoint.
	terraform -chdir=$(TF_DIR) destroy $(TF_APP_VARS) -refresh=false -auto-approve

.PHONY: clean
clean: ## Remove the state backend and its data (run after down)
	$(COMPOSE) down -v

.PHONY: info
info: ## Print the UI addresses and credentials
	@echo "UIs (through the Istio ingress gateway):"
	@terraform -chdir=$(TF_DIR) output -json urls | \
	  python3 -c 'import json,sys; [print(f"  {k:<13} {v}") for k,v in sorted(json.load(sys.stdin).items())]'
	@echo "Credentials:"
	@echo "  grafana       admin / $$(terraform -chdir=$(TF_DIR) output -raw grafana_admin_password)"
	@echo "  argocd        admin / $$(kubectl --context $$(terraform -chdir=$(TF_DIR) output -raw kubeconfig_context) \
	  -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"

.PHONY: verify
verify: ## Smoke test: app, metrics, logs, traces and mesh
	./scripts/verify.sh

.PHONY: chaos
chaos: ## Make inventory fail 50% of the requests (fires SLO alerts)
	terraform -chdir=$(TF_DIR) apply $(TF_APP_VARS) -var inventory_fault_rate=0.5 -auto-approve

.PHONY: chaos-off
chaos-off: ## Restore the inventory fault rate from the tfvars file
	terraform -chdir=$(TF_DIR) apply $(TF_APP_VARS) -auto-approve

.PHONY: lint
lint: ## Static checks (terraform fmt/validate, helm lint)
	terraform -chdir=$(TF_DIR) fmt -check -recursive
	terraform -chdir=$(TF_DIR) init -backend=false -input=false >/dev/null
	terraform -chdir=$(TF_DIR) validate
	helm lint $(TF_DIR)/modules/sample-app/chart $(TF_DIR)/modules/service-mesh/chart
