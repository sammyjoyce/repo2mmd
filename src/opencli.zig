const std = @import("std");

pub const opencli_spec =
    \\{
    \\  "opencli": "0.1",
    \\  "info": {
    \\    "title": "repo2mmd",
    \\    "summary": "Repository to Mermaid diagram generator",
    \\    "description": "Scan repositories and emit Mermaid diagrams that reflect code structure with certainty tags.",
    \\    "version": "0.1.0",
    \\    "contact": {
    \\      "name": "Sam Joyce",
    \\      "url": "https://github.com/sammyjoyce/repo2mmd",
    \\      "email": "sam@example.com"
    \\    },
    \\    "license": {
    \\      "name": "MIT License",
    \\      "identifier": "MIT"
    \\    }
    \\  },
    \\  "conventions": {
    \\    "groupOptions": false,
    \\    "optionArgumentSeparator": " "
    \\  },
    \\  "arguments": [
    \\    {
    \\      "name": "command",
    \\      "required": true,
    \\      "arity": {
    \\        "minimum": 1,
    \\        "maximum": 1
    \\      },
    \\      "description": "The command to execute"
    \\    }
    \\  ],
    \\  "options": [
    \\    {
    \\      "name": "help",
    \\      "required": false,
    \\      "aliases": ["h"],
    \\      "arguments": [],
    \\      "description": "Show help message and exit"
    \\    },
    \\    {
    \\      "name": "version",
    \\      "required": false,
    \\      "aliases": ["V"],
    \\      "arguments": [],
    \\      "description": "Show version information and exit"
    \\    }
    \\  ],
    \\  "commands": [
    \\    {
    \\      "name": "graph",
    \\      "aliases": [],
    \\      "description": "Generate repository graphs",
    \\      "options": [
    \\        {
    \\          "name": "root",
    \\          "required": false,
    \\          "aliases": [],
    \\          "arguments": [
    \\            {
    \\              "name": "path",
    \\              "required": true,
    \\              "arity": {
    \\                "minimum": 1,
    \\                "maximum": 1
    \\              },
    \\              "description": "Override the repository root (default: current directory)"
    \\            }
    \\          ],
    \\          "description": "Override the repository root"
    \\        },
    \\        {
    \\          "name": "format",
    \\          "required": false,
    \\          "aliases": [],
    \\          "arguments": [
    \\            {
    \\              "name": "kind",
    \\              "required": true,
    \\              "arity": {
    \\                "minimum": 1,
    \\                "maximum": 1
    \\              },
    \\              "acceptedValues": ["text", "json"],
    \\              "description": "Select output format: text (default) or json"
    \\            }
    \\          ],
    \\          "description": "Select output format"
    \\        }
    \\      ],
    \\      "arguments": [],
    \\      "examples": [
    \\        "repo2mmd graph",
    \\        "repo2mmd graph --root /path/to/repo",
    \\        "repo2mmd graph --format json",
    \\        "repo2mmd graph --root /path/to/repo --format json"
    \\      ]
    \\    },
    \\    {
    \\      "name": "explain",
    \\      "aliases": [],
    \\      "description": "Explain graph edges",
    \\      "options": [],
    \\      "arguments": [],
    \\      "examples": [
    \\        "repo2mmd explain"
    \\      ],
    \\      "metadata": {
    \\        "status": "stub"
    \\      }
    \\    },
    \\    {
    \\      "name": "init",
    \\      "aliases": [],
    \\      "description": "Bootstrap configuration",
    \\      "options": [],
    \\      "arguments": [],
    \\      "examples": [
    \\        "repo2mmd init"
    \\      ],
    \\      "metadata": {
    \\        "status": "stub"
    \\      }
    \\    },
    \\    {
    \\      "name": "cache",
    \\      "aliases": [],
    \\      "description": "Inspect analysis cache",
    \\      "options": [],
    \\      "arguments": [],
    \\      "examples": [
    \\        "repo2mmd cache"
    \\      ],
    \\      "metadata": {
    \\        "status": "stub"
    \\      }
    \\    }
    \\  ],
    \\  "exitCodes": [
    \\    {
    \\      "code": 0,
    \\      "description": "Success"
    \\    },
    \\    {
    \\      "code": 1,
    \\      "description": "General error"
    \\    },
    \\    {
    \\      "code": 2,
    \\      "description": "Invalid command or argument"
    \\    }
    \\  ],
    \\  "examples": [
    \\    "repo2mmd graph",
    \\    "repo2mmd graph --root ./my-project",
    \\    "repo2mmd graph --format json",
    \\    "repo2mmd explain",
    \\    "repo2mmd init",
    \\    "repo2mmd cache",
    \\    "repo2mmd --help",
    \\    "repo2mmd --version"
    \\  ],
    \\  "interactive": false,
    \\  "metadata": [
    \\    {
    \\      "name": "language",
    \\      "value": {
    \\        "implementation": "Zig",
    \\        "version": "0.15.1"
    \\      }
    \\    },
    \\    {
    \\      "name": "build",
    \\      "value": {
    \\        "system": "Zig build system"
    \\      }
    \\    }
    \\  ]
    \\}
;
