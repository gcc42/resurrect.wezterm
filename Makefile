.PHONY: test test-verbose check lint all clean help

help:
	@echo "Available targets:"
	@echo "  make test         - Run all tests"
	@echo "  make test-verbose - Run tests with verbose output"
	@echo "  make check        - Run type check with LuaLS"
	@echo "  make lint         - Run linter with luacheck"
	@echo "  make all          - Run all checks (lint, check, test)"
	@echo "  make clean        - Clean generated files"
	@echo "  make help         - Show this help"

# Run tests
test:
	@lua plugin/resurrect/test/init.lua

test-verbose:
	@lua plugin/resurrect/test/init.lua --verbose

# Type check with LuaLS (excluding test directory)
check:
	@echo "Running type check..."
	@lua-language-server --check . --checklevel=Warning --logpath=.lua-check-logs
	@echo "Type check passed"

# Lint with luacheck
lint:
	@echo "Running linter..."
	@luacheck plugin/resurrect --no-unused-args --max-line-length=120
	@echo "Lint passed"

# Run all checks
all: lint check test
	@echo "All checks passed"

# Clean generated files
clean:
	@rm -rf .lua-check-logs
