# Test Fixtures for repo2mmd

This directory contains test fixtures for the repo2mmd project, designed to validate the language frontends and graph generation capabilities.

## Structure

```
test/fixtures/
├── README.md                 # This file
├── zig/                     # Zig language fixtures
│   ├── main.zig             # Main entry point with imports
│   ├── auth.zig             # Authentication module
│   └── database.zig         # Database module
├── c/                       # C language fixtures
│   ├── main.c               # Main entry point
│   ├── auth.c               # Authentication implementation
│   ├── auth.h               # Authentication header
│   ├── database.c           # Database implementation
│   └── database.h           # Database header
└── typescript/              # TypeScript language fixtures
    ├── index.ts             # Main entry point
    ├── auth.ts              # Authentication module
    ├── database.ts          # Database module
    ├── package.json         # Node.js project configuration
    └── tsconfig.json        # TypeScript configuration
```

## Fixture Design

Each language fixture implements the same basic application structure:

1. **Main module** - Entry point that orchestrates authentication and database operations
2. **Authentication module** - User authentication with mock credentials
3. **Database module** - User data storage and retrieval

This consistent structure allows for:
- Cross-language comparison of graph generation
- Validation of import/include dependency detection
- Testing of function call relationship extraction
- Verification of type relationship analysis

## Expected Graph Characteristics

### Zig Fixtures
- **Nodes**: 3 (main, authenticate, init)
- **Edges**: 4 (2 calls, 2 imports)
- **Features**: `@import` statements, function calls, error handling

### C Fixtures  
- **Nodes**: 4 (main, auth_authenticate, db_init, run_app)
- **Edges**: 6 (3 calls, 2 includes, 1 additional call)
- **Features**: Header includes, function pointers, struct definitions

### TypeScript Fixtures
- **Nodes**: 4 (main, authenticate, Database class, runApp)
- **Edges**: 5 (2 calls, 1 instantiation, 2 imports)
- **Features**: ES6 imports, async/await, class definitions

## Golden Files

Corresponding golden files are stored in `test/golden/`:

- `*_deps_golden.json` - Expected JSON IR output
- `*_deps_golden.mmd` - Expected Mermaid diagram output

These files serve as test vectors to ensure deterministic output and catch regressions.

## Usage in Tests

The `fixtures_test.zig` file demonstrates how to use these fixtures:

```zig
test "fixture validation" {
    for (fixture_cases) |case| {
        // Validate fixture files exist
        // Check golden file structure
        // Verify expected node/edge counts
    }
}
```

## Adding New Fixtures

When adding new language fixtures:

1. Create directory under `test/fixtures/<language>/`
2. Implement the standard application structure
3. Generate corresponding golden files
4. Update `fixture_cases` in `fixtures_test.zig`
5. Update this README

## Notes

- Fixtures use mock implementations to avoid external dependencies
- All fixtures are self-contained and compilable
- Golden files should be updated when fixture logic changes
- Follow existing naming conventions for consistency