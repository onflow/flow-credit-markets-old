

.PHONY: ci
ci: lint test

.PHONY: lint
lint:
	flow cadence lint --base-dir=cadence --warnings-as-errors

.PHONY: test
test:
	flow test
