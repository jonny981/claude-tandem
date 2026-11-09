.PHONY: test lint

test:
	./test/run_tests.sh

lint:
	shellcheck --severity=warning plugins/tandem/scripts/*.sh
