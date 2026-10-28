# Testing Strategy for repo2mmd

This document outlines the testing approach and build steps for the repo2mmd project.

## Test Suite Structure

### Main Test Suite (`zig build test`)
- **Purpose**: Fast, unit-level tests for core functionality
- **Location**: `test/main.zig` and related modules
- **Frequency**: Run frequently during development
- **Scope**: Core algorithms, data structures, CLI parsing
- **Runtime**: < 30 seconds

### Fixtures Test Suite (`zig build test-fixtures`)
- **Purpose**: Validate language frontends with realistic code samples
- **Location**: `test/fixtures_test.zig` with fixtures in `test/fixtures/`
- **Frequency**: Run less frequently (e.g., before commits, in CI)
- **Scope**: Cross-language dependency analysis, golden file validation
- **Runtime**: 1-2 minutes

### Integration Tests (`zig build test-integration`)
- **Purpose**: Complete end-to-end validation
- **Components**: Main test suite + fixtures test suite
- **Frequency**: Run in CI pipelines, before releases
- **Scope**: Full system validation
- **Runtime**: 2-5 minutes

## Build Commands

### Development Workflow
```bash
# Fast iteration - run core tests only
just test                    # or: zig build test

# Before commits - run fixtures too
just test-fixtures           # or: zig build test-fixtures

# Full validation - run everything
just test-integration        # or: zig build test-integration
```

### CI Pipeline
```bash
# Primary CI command
zig build test-integration
```

## Fixtures Testing

### Fixture Structure
Each language fixture implements a consistent application pattern:
- **Entry point**: Main orchestrator
- **Authentication**: User validation module
- **Database**: Data persistence module

### Golden Files
- **JSON IR**: Expected intermediate representation (`*_deps_golden.json`)
- **Mermaid**: Expected diagram output (`*_deps_golden.mmd`)

### Validation Criteria
- File existence and readability
- JSON schema compliance
- Mermaid diagram structure
- Expected node/edge counts
- Cross-language consistency

## Test Categories

### Unit Tests
- Scheduler algorithms
- IR serialization/deserialization
- Discovery mechanisms
- Diagnostic handling

### Integration Tests
- End-to-end CLI workflows
- Language frontend validation
- Cache behavior
- Performance benchmarks

### Regression Tests
- Golden file comparison
- Deterministic output validation
- Schema version compatibility

## Performance Testing

### Benchmarks
- Cold cache analysis time
- Warm cache analysis time
- Memory usage patterns
- Large repository handling

### Performance Targets
- Cold run: ≤ 90 seconds for 1M LOC
- Warm run: ≤ 5 seconds for 100-file changes
- Memory: Configurable via `--max-bytes`

## Quality Gates

### Pre-commit
- Core test suite passes
- Code formatting valid
- No compilation warnings

### Pre-merge
- Integration tests pass
- Golden files updated (if needed)
- Performance benchmarks within limits

### Release
- Full test suite passes
- Documentation updated
- Performance targets met
- Security review completed

## Adding New Tests

### New Language Frontend
1. Create fixture directory in `test/fixtures/<language>/`
2. Implement standard application pattern
3. Generate golden files
4. Add test case to `fixtures_test.zig`
5. Update documentation

### New Feature
1. Add unit tests to appropriate test module
2. Update fixtures if affecting language analysis
3. Regenerate golden files if needed
4. Update integration tests

## Troubleshooting

### Common Issues
- **Golden file mismatches**: Regenerate after fixture changes
- **JSON parsing errors**: Validate JSON syntax with `python3 -m json.tool`
- **Fixture compilation errors**: Check language-specific syntax
- **Performance regressions**: Run benchmarks to identify bottlenecks

### Debug Commands
```bash
# Validate JSON syntax
python3 -m json.tool test/golden/*.json

# Run specific test
zig test test/fixtures_test.zig

# Verbose test output
zig build test-fixtures --verbose
```

## Continuous Integration

### GitHub Actions
```yaml
- name: Run Core Tests
  run: zig build test

- name: Run Fixtures Tests  
  run: zig build test-fixtures

- name: Run Integration Tests
  run: zig build test-integration
```

### Local CI Simulation
```bash
# Simulate full CI pipeline
zig build fmt-check && \
zig build test-integration && \
zig build perf
```

This testing strategy ensures fast development iteration while maintaining comprehensive validation of the repo2mmd system across all supported languages.