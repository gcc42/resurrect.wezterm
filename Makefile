.PHONY: test test-verbose check lint fix all clean help

help:
	@echo "Available targets:"
	@echo "  make test         - Run all tests"
	@echo "  make test-verbose - Run tests with verbose output"
	@echo "  make check        - Run type check with LuaLS"
	@echo "  make lint         - Run linter with luacheck"
	@echo "  make fix          - Format code with stylua"
	@echo "  make all          - Run all checks (fix, lint, check, test)"
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
	@luacheck plugin/resurrect --no-unused-args --max-line-length=120 --exclude-files="**/test/lib/**" --exclude-files="**/types/**"
	@echo "Lint passed"

# Format with stylua
fix:
	@echo "Formatting code..."
	@stylua plugin/ -g "*.lua" -g "!**/test/lib/**"
	@echo "Formatting complete"

# Run all checks
all: fix lint check test
	@echo "All checks passed"

# Clean generated files
clean:
	@rm -rf .lua-check-logs
