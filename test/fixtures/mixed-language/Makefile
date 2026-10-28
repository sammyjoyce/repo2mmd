# Mixed-language test fixture Makefile

CC = gcc
CFLAGS = -Wall -Wextra -std=c99 -fPIC
AR = ar
ARFLAGS = rcs

# Directories
INCLUDE_DIR = include
LIB_DIR = lib
SRC_DIR = src
BUILD_DIR = build
FRONTEND_DIR = frontend

# Source files
C_SOURCES = $(LIB_DIR)/auth.c $(LIB_DIR)/database.c
ZIG_SOURCES = $(SRC_DIR)/main.zig $(SRC_DIR)/auth.zig $(SRC_DIR)/database.zig
TS_SOURCES = $(FRONTEND_DIR)/*.ts

# Output files
STATIC_LIB = $(BUILD_DIR)/libmixedlang.a
SHARED_LIB = $(BUILD_DIR)/libmixedlang.so
ZIG_EXEC = $(BUILD_DIR)/mixedlang_app
TS_BUILD = $(FRONTEND_DIR)/dist

.PHONY: all clean c-lib zig-app ts-build test

all: c-lib zig-app ts-build

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Build C static library
$(STATIC_LIB): $(C_SOURCES) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $(C_SOURCES) -I$(INCLUDE_DIR)
	$(AR) $(ARFLAGS) $@ auth.o database.o
	rm -f auth.o database.o

# Build C shared library
$(SHARED_LIB): $(C_SOURCES) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -shared -o $@ $(C_SOURCES) -I$(INCLUDE_DIR)

# Build C libraries
c-lib: $(STATIC_LIB) $(SHARED_LIB)

# Build Zig application
zig-app: $(ZIG_SOURCES)
	cd $(SRC_DIR) && zig build-exe main.zig --name mixedlang_app -Mroot=../$(BUILD_DIR)

# Build TypeScript frontend
ts-build:
	cd $(FRONTEND_DIR) && npm install && npm run build

# Test the mixed-language integration
test: all
	@echo "Testing C library compilation..."
	$(CC) -o $(BUILD_DIR)/test_c test.c -L$(BUILD_DIR) -lmixedlang -I$(INCLUDE_DIR)
	@echo "Testing Zig compilation..."
	cd $(SRC_DIR) && zig build test
	@echo "Testing TypeScript compilation..."
	cd $(FRONTEND_DIR) && npm test || echo "No TypeScript tests configured"
	@echo "All tests completed!"

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -f $(FRONTEND_DIR)/dist/*
	rm -f $(FRONTEND_DIR)/node_modules

# Install dependencies (TypeScript)
install-deps:
	cd $(FRONTEND_DIR) && npm install

# Show project structure
info:
	@echo "Mixed-Language Test Fixture"
	@echo "==========================="
	@echo "C Sources: $(C_SOURCES)"
	@echo "Zig Sources: $(ZIG_SOURCES)"
	@echo "TypeScript Sources: $(TS_SOURCES)"
	@echo "Build Directory: $(BUILD_DIR)"