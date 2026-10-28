# Justfile for repo2mmd

# Build the project
build:
    zig build

default: build

# Build with release optimization
release:
    zig build -Doptimize=ReleaseSafe

# Build reproducible release archives into dist/
dist:
    ./scripts/release.sh

# Regenerate the README example from its pinned public commit
example: build
    ./scripts/example.sh

# Run the application (with optional arguments)
run *args:
    zig build run -- {{ args }}

# Run tests
test:
    zig build test

# Run fixtures tests (less frequent)
test-fixtures:
    zig build test-fixtures

# Run all tests including fixtures (for CI)
test-integration:
    zig build test-integration

# Run tests with different optimization levels
test-debug:
    zig build test -Doptimize=Debug

test-release:
    zig build test -Doptimize=ReleaseSafe

test-fast:
    zig build test -Doptimize=ReleaseFast

# Check code formatting
fmt:
    zig build fmt

fmt-check:
    zig build fmt-check

# Run all checks
check:
    zig build check

# Clean build artifacts
clean:
    zig build clean

# Install dependencies (if any)
install:
    # No additional installation needed for this template
    echo "No additional installation needed"

# Generate documentation
docs:
    # Generate documentation using your preferred tool
    echo "Documentation generation not configured"

# Display help
help:
    echo "Available commands:"
    echo "  build           - Build the project"
    echo "  release         - Build with release optimization"
    echo "  dist            - Build reproducible release archives into dist/"
    echo "  example         - Regenerate examples/zig-clap from its pinned commit"
    echo "  run             - Run the application"
    echo "  test            - Run main test suite (fast)"
    echo "  test-fixtures   - Run fixtures test suite (less frequent)"
    echo "  test-integration- Run all tests including fixtures (for CI)"
    echo "  test-debug      - Run tests with debug optimization"
    echo "  test-release    - Run tests with release optimization"
    echo "  test-fast       - Run tests with fast optimization"
    echo "  fmt             - Format code"
    echo "  fmt-check       - Check code formatting"
    echo "  check           - Run all checks"
    echo "  clean           - Clean build artifacts"
    echo "  install         - Install dependencies"
    echo "  docs            - Generate documentation"
    echo "  help            - Display this help message"
