# Developer shortcuts for the agent-sdlc repo itself. help is the default goal so a
# bare `make` documents what is available.
.DEFAULT_GOAL := help

.PHONY: help test test-one ci

help: ## List available targets
	@echo "agent-sdlc - available targets:"
	@echo ""
	@echo "  test            Run every test suite (tests/run.sh)"
	@echo "  test-one S=name Run a single suite, e.g. make test-one S=validate-sheet"
	@echo "  ci              Run the tests workflow locally in a container (act)"

test: ## Run every test suite
	./tests/run.sh

# Run one suite by folder name under tests/, e.g. make test-one S=agent-runner.
test-one: ## Run a single suite (S=<name>)
	@test -n "$(S)" || { echo "usage: make test-one S=<suite-name> (a folder under tests/)" >&2; exit 64; }
	./tests/run.sh $(S)

# Reproduce CI locally: act runs .github/workflows/test.yml in a container, the same
# clean environment the GitHub runner uses, catching env-portability bugs that a
# local tests/run.sh cannot (e.g. a missing git identity). Image reuse and the
# runner image are pinned in ~/.actrc.
ci: ## Run the tests workflow locally with act
	act pull_request -W .github/workflows/test.yml
