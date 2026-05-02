# Jda Language - Top-level Makefile
# Requires Docker for Linux x86-64 builds.

IMAGE = jda-build
DOCKER_PLATFORM = linux/amd64

.PHONY: docker-build stage0 test-stage0 selfhost-stage1 ci-selfhost-roundtrip ci-stage0 ci-stage0-conformance ci-stage1-conformance fmt-check lint docs docs-check quality analyze-features split-source compile-demo clean

docker-build:
	docker build --platform=$(DOCKER_PLATFORM) -t $(IMAGE) -f docker/Dockerfile .

stage0: docker-build
	docker run --rm \
		--platform=$(DOCKER_PLATFORM) \
		-v $(PWD):/jda \
		-w /jda/bootstrap/stage0 \
		$(IMAGE) \
		make all

test-stage0: stage0
	docker run --rm \
		--platform=$(DOCKER_PLATFORM) \
		-v $(PWD):/jda \
		-w /jda/bootstrap/stage0 \
		$(IMAGE) \
		make test

selfhost-stage1: stage0
	docker run --rm \
		--platform=$(DOCKER_PLATFORM) \
		-v $(PWD):/jda \
		-w /jda/bootstrap/stage0 \
		$(IMAGE) \
		bash -lc './jda0 ../stage1/jda1.jda /tmp/jda1 && chmod +x /tmp/jda1 && /tmp/jda1 /jda/examples/hello.jda /tmp/hello_from_stage1 && chmod +x /tmp/hello_from_stage1 && /tmp/hello_from_stage1'

test-if: stage0
	docker run --rm \
		--platform=$(DOCKER_PLATFORM) \
		-v $(PWD):/jda \
		-w /jda/bootstrap/stage0 \
		$(IMAGE) \
		bash -lc './jda0 ../stage1/jda1.jda /tmp/jda1 && chmod +x /tmp/jda1 && /tmp/jda1 /jda/examples/test_if.jda /tmp/test_if && chmod +x /tmp/test_if && /tmp/test_if'


ci-selfhost-roundtrip: stage0
	docker run --rm \
		--platform=$(DOCKER_PLATFORM) \
		-v $(PWD):/jda \
		-w /jda \
		$(IMAGE) \
		bash tools/ci/selfhost_roundtrip.sh

ci-stage0: docker-build
	docker run --rm \
		--platform=$(DOCKER_PLATFORM) \
		-v $(PWD):/jda \
		-w /jda \
		$(IMAGE) \
		bash tools/ci/stage0_smoke.sh

ci-stage0-conformance: docker-build
	docker run --rm \
		--platform=$(DOCKER_PLATFORM) \
		-v $(PWD):/jda \
		-w /jda \
		$(IMAGE) \
		bash tools/ci/stage0_conformance.sh

ci-stage1-conformance: docker-build
	docker run --rm \
		--platform=$(DOCKER_PLATFORM) \
		-v $(PWD):/jda \
		-w /jda \
		$(IMAGE) \
		bash tools/ci/stage1_conformance.sh

fmt-check:
	bash tools/dev/fmt_check.sh

lint:
	bash tools/dev/lint.sh

docs:
	bash tools/dev/generate_docs.sh

docs-check:
	bash tools/dev/docs_check.sh

quality: fmt-check lint docs-check

analyze-features:
	@echo "Analyzing Jda source files for feature usage..."
	python3 tools/dev/source_analyzer.py bootstrap/stage1/jda1.jda

split-source:
	@echo "Analyzing source split strategies..."
	python3 tools/dev/source_splitter.py bootstrap/stage1/jda1.jda

compile-demo:
	@echo "Running compilation workflow (analysis mode)..."
	bash tools/dev/compile_workflow.sh bootstrap/stage1/jda1.jda /tmp/jda1_demo --analyze

clean:
	docker run --rm \
		--platform=$(DOCKER_PLATFORM) \
		-v $(PWD):/jda \
		-w /jda/bootstrap/stage0 \
		$(IMAGE) \
		make clean
