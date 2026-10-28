# Mixed Language Test Fixture

This fixture tests cross-language symbol resolution and dependency analysis with C, Zig, and TypeScript components.

## Project Structure

```
mixed-language/
├── src/                    # Zig application modules
│   ├── main.zig           # Main application entry point
│   ├── auth.zig           # Authentication module using C functions
│   └── database.zig       # Database module using C functions
├── frontend/              # TypeScript frontend
│   ├── main.ts            # Frontend application entry point
│   ├── auth.ts            # Authentication service
│   ├── database.ts        # Database connection service
│   ├── package.json       # Node.js dependencies
│   └── tsconfig.json      # TypeScript configuration
├── lib/                   # C implementation files
│   ├── auth.c             # Authentication implementation
│   └── database.c         # Database implementation
├── include/               # C header files
│   ├── auth.h             # Authentication interface
│   └── database.h         # Database interface
├── Makefile              # Build configuration for C components
└── README.md             # This file
```

## Cross-Language Dependencies

### C → Zig
- C functions exported through headers for Zig to import
- Database and authentication APIs

### Zig → C
- Zig modules import C functions using `@cImport`
- `auth.zig` imports `authenticate_user`, `validate_session`, `logout_session`
- `database.zig` imports `database_connect`, `database_load_user`, etc.

### TypeScript → Zig (conceptual)
- TypeScript services designed to work with Zig backend
- Shared data structures and interfaces
- Authentication and database services mirror Zig functionality

## Key Features Tested

1. **Symbol Resolution Across Languages**
   - Function names and signatures
   - Data structures and type definitions
   - Import/export relationships

2. **Dependency Graph Construction**
   - Inter-language module dependencies
   - Function call relationships
   - Data flow analysis

3. **Build System Integration**
   - C compilation with Makefile
   - Zig compilation with build system
   - TypeScript compilation with npm/tsc

## Build Instructions

```bash
# Build all components
make all

# Build individual components
make c-lib      # C static and shared libraries
make zig-app    # Zig application
make ts-build   # TypeScript frontend

# Run tests
make test

# Clean build artifacts
make clean
```

## Expected Resolution Rate

≥93% of edges should be resolved across all languages, including:
- C function definitions and declarations
- Zig import statements and C function calls
- TypeScript module imports and function references
- Cross-language data structure dependencies

## Test Scenarios

1. **Authentication Flow**: C implementation → Zig usage → TypeScript frontend
2. **Database Operations**: C implementation → Zig data access → TypeScript service layer
3. **Type Compatibility**: Shared data structures across language boundaries
4. **Build Dependencies**: Makefile targets, Zig build system, npm package management