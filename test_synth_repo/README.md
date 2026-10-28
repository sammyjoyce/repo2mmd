# Synthetic Test Repository

This is a synthetic repository created for testing the repo2mmd tool.

## Structure

- `src/main.zig` - Main entry point that imports auth and database modules
- `src/auth.zig` - Authentication module with User struct
- `src/database.zig` - Database module with Database struct

## Expected Dependencies

- `main.zig` imports `auth.zig` and `database.zig`
- No circular dependencies
- All imports are static