# Jda Language - Top-level Makefile
# Requires Docker for Linux x86-64 builds.

IMAGE = jda-build

.PHONY: docker-build stage0 test-stage0 clean

docker-build:
	docker build -t $(IMAGE) -f docker/Dockerfile .

stage0: docker-build
	docker run --rm \
		-v $(PWD):/jda \
		-w /jda/bootstrap/stage0 \
		$(IMAGE) \
		make all

test-stage0: stage0
	docker run --rm \
		-v $(PWD):/jda \
		-w /jda/bootstrap/stage0 \
		$(IMAGE) \
		make test

clean:
	docker run --rm \
		-v $(PWD):/jda \
		-w /jda/bootstrap/stage0 \
		$(IMAGE) \
		make clean
