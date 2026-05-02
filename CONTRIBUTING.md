# Contributing to Jda

See [docs/contributing/CONTRIBUTING.md](docs/contributing/CONTRIBUTING.md) for the full contributing guide.

Quick start:

1. Fork and clone the repo
2. Build Docker image: `docker build -t jda-build docker/`
3. Make changes
4. Run tests: `docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 -v $(PWD):/jda -w /jda jda-build bash tools/run_tests.sh`
5. Open a PR
