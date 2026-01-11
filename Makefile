.PHONY: test test-verbose help

help:
	@echo "Available targets:"
	@echo "  make test         - Run all tests"
	@echo "  make test-verbose - Run tests with verbose output"
	@echo "  make help         - Show this help"

test:
	@lua plugin/resurrect/test/init.lua

test-verbose:
	@lua plugin/resurrect/test/init.lua --verbose
