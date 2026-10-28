const std = @import("std");

// Node kinds matching C header
pub const NodeKind = enum {
    Module,
    File,
    Type,
    Func,
    Var,

    pub fn toString(self: NodeKind) []const u8 {
        return switch (self) {
            .Module => "module",
            .File => "file",
            .Type => "type",
            .Func => "func",
            .Var => "var",
        };
    }
};

// Edge relationships matching C header
pub const EdgeRel = enum {
    Imports,
    Includes,
    Calls,
    Contains,
    Extends,
    Implements,

    pub fn toString(self: EdgeRel) []const u8 {
        return switch (self) {
            .Imports => "imports",
            .Includes => "includes",
            .Calls => "calls",
            .Contains => "contains",
            .Extends => "extends",
            .Implements => "implements",
        };
    }
};

// Certainty levels matching C header
pub const Certainty = enum {
    Static,
    Indirect,
    Dynamic,
    Comptime,
    Unknown,

    pub fn toString(self: Certainty) []const u8 {
        return switch (self) {
            .Static => "static",
            .Indirect => "indirect",
            .Dynamic => "dynamic",
            .Comptime => "comptime",
            .Unknown => "unknown",
        };
    }
};

// Visibility levels matching C header
pub const Visibility = enum {
    Public,
    Private,
    Package,

    pub fn toString(self: Visibility) []const u8 {
        return switch (self) {
            .Public => "public",
            .Private => "private",
            .Package => "package",
        };
    }
};

// Diagnostic severity matching C header
pub const Severity = enum {
    Info,
    Warn,
    Error,

    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .Info => "info",
            .Warn => "warn",
            .Error => "error",
        };
    }
};

pub const Position = struct {
    line: u32,
    column: u32,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

// Node structure matching C header exactly
pub const Node = struct {
    id: []const u8,
    lang: []const u8,
    kind: NodeKind,
    name: []const u8,
    fqname: []const u8,
    file: []const u8,
    range: Range,
    signature: ?[]const u8,
    visibility: Visibility,
    origin_plugin: []const u8,
    module_id: ?[]const u8,
    tags: []const []const u8,
};

pub const Edge = struct {
    src: []const u8,
    dst: []const u8,
    rel: EdgeRel,
    certainty: Certainty,
    certainty_reason: ?[]const u8,
    evidence_paths: []const []const u8,
    evidence_lines: []const u32,
    diagnostics: []const DiagnosticRef,
};

pub const DiagnosticRef = struct {
    id: []const u8,
};

pub const Diagnostic = struct {
    id: []const u8,
    severity: Severity,
    message: []const u8,
    file: []const u8,
    range: Range,
    tags: []const []const u8,
};

pub const Graph = struct {
    nodes: []const Node,
    edges: []const Edge,
};

pub const PluginSummary = struct {
    id: []const u8,
    version: []const u8,
    schema_min: u32,
    schema_max: u32,
};

pub const GraphManifest = struct {
    generated_at: []const u8,
    generator_version: []const u8,
    graph_type: []const u8,
    input_root: []const u8,
    schema_version: u32,
    node_count: u32,
    edge_count: u32,
    resolved_refs: u32,
    unresolved_refs: u32,
    resolution_rate: f32,
    cache_hits: u32,
    cache_misses: u32,
    plugins_used: []const PluginSummary,
    cli_args: []const []const u8,
};

pub const FullDiagnostic = struct {
    id: []const u8,
    severity: Severity,
    code: []const u8,
    message: []const u8,
    file: ?[]const u8,
    range: ?Range,
    plugin: ?[]const u8,
};

// Main IR structure matching C header
pub const IR = struct {
    schema_version: u32,
    graph: Graph,
    manifest: GraphManifest,
    diagnostics: []const FullDiagnostic,
};
