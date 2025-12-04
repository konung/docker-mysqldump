.PHONY: build push build-local shell run help clean rebuild

VERSION := 3.0.0
IMAGE   := konung/mariadb-dump

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build and push image to registry (x86-64 only)
	docker buildx build --push --platform linux/amd64 -t $(IMAGE):$(VERSION) -t $(IMAGE):latest .

build-local: ## Build image for local testing
	docker build -t $(IMAGE):local .

shell: build-local ## Start interactive shell in container
	docker run -it --rm \
		-v $(PWD)/sqldata:/path_to_backups_dir_on_host \
		--env-file .env.dev \
		$(IMAGE):local /bin/bash

run: build-local ## Run backup script locally
	docker run -it --rm \
		-v $(PWD)/sqldata:/path_to_backups_dir_on_host \
		--env-file .env.dev \
		$(IMAGE):local ruby backup_sql_replica.rb

console: build-local ## Start IRB console with backuplib loaded
	docker run -it --rm \
		-v $(PWD)/sqldata:/path_to_backups_dir_on_host \
		--env-file .env.dev \
		$(IMAGE):local bundle exec irb -r ./backuplib.rb

clean: ## Remove local Docker image and build cache
	docker rmi $(IMAGE):local 2>/dev/null || true
	docker builder prune -f

rebuild: clean ## Force full rebuild (no cache)
	docker build --no-cache -t $(IMAGE):local .
