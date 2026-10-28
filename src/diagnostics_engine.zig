const std = @import("std");
const ir = @import("ir");
const diag = @import("diag");

/// Diagnostic categories for better organization
pub const DiagnosticCategory = enum {
    /// Symbol resolution issues
    Resolution,
    /// Parsing and syntax issues
    Parsing,
    /// Plugin-related issues
    Plugin,
    /// Performance and resource issues
    Performance,
    /// Configuration issues
    Configuration,
    /// General information
    Info,
};

/// Root cause tags for unresolved references
pub const RootCauseTag = enum {
    /// Symbol not found in any scope
    SymbolNotFound,
    /// Symbol found but not accessible (visibility)
    NotAccessible,
    /// Symbol found in different language
    CrossLanguage,
    /// Circular dependency detected
    CircularDependency,
    /// Module not found
    ModuleNotFound,
    /// Type mismatch
    TypeMismatch,
    /// File not found
    FileNotFound,
    /// Plugin error
    PluginError,
    /// Unknown cause
    Unknown,
};

/// Enhanced diagnostic with root cause analysis
pub const EnhancedDiagnostic = struct {
    id: []const u8,
    severity: ir.Severity,
    category: DiagnosticCategory,
    code: []const u8,
    message: []const u8,
    file: ?[]const u8,
    range: ?ir.Range,
    plugin: ?[]const u8,
    root_cause: RootCauseTag,
    suggestions: []const []const u8,
    related_symbols: []const []const u8,
    evidence: DiagnosticEvidence,

    pub fn deinit(self: *EnhancedDiagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.code);
        allocator.free(self.message);
        if (self.file) |file| allocator.free(file);
        if (self.plugin) |plugin| allocator.free(plugin);
        for (self.suggestions) |suggestion| allocator.free(suggestion);
        allocator.free(self.suggestions);
        allocator.free(self.related_symbols);
        self.evidence.deinit(allocator);
    }
};

/// Evidence supporting a diagnostic
pub const DiagnosticEvidence = struct {
    /// File paths where the issue was detected
    files: []const []const u8,
    /// Line numbers where the issue occurs
    lines: []const u32,
    /// Code snippets showing the issue
    code_snippets: []const []const u8,
    /// Related node IDs
    node_ids: []const []const u8,

    pub fn deinit(self: *DiagnosticEvidence, allocator: std.mem.Allocator) void {
        allocator.free(self.files);
        allocator.free(self.lines);
        for (self.code_snippets) |snippet| allocator.free(snippet);
        allocator.free(self.code_snippets);
        for (self.node_ids) |node_id| allocator.free(node_id);
        allocator.free(self.node_ids);
    }
};

/// Diagnostic thresholds configuration
pub const DiagnosticThresholds = struct {
    /// Maximum warnings before escalating to error
    max_warnings: u32 = 50,
    /// Maximum errors before failing
    max_errors: u32 = 10,
    /// Maximum unresolved references before failing
    max_unresolved: u32 = 20,
    /// Categories to suppress
    suppressed_categories: []const DiagnosticCategory = &[_]DiagnosticCategory{},
    /// Specific error codes to suppress
    suppressed_codes: []const []const u8 = &[_][]const u8{},
};

/// Diagnostic engine with root cause analysis
pub const DiagnosticEngine = struct {
    allocator: std.mem.Allocator,
    thresholds: DiagnosticThresholds,
    diagnostics: std.ArrayList(EnhancedDiagnostic),

    // Statistics
    stats: struct {
        total_diagnostics: u32,
        by_severity: [3]u32, // Info, Warn, Error
        by_category: [@typeInfo(DiagnosticCategory).@"enum".fields.len]u32,
        by_root_cause: [@typeInfo(RootCauseTag).@"enum".fields.len]u32,
    },

    pub fn init(allocator: std.mem.Allocator, thresholds: DiagnosticThresholds) !DiagnosticEngine {
        return DiagnosticEngine{
            .allocator = allocator,
            .thresholds = thresholds,
            .diagnostics = try std.ArrayList(EnhancedDiagnostic).initCapacity(allocator, 0),
            .stats = .{
                .total_diagnostics = 0,
                .by_severity = .{0} ** 3,
                .by_category = .{0} ** @typeInfo(DiagnosticCategory).@"enum".fields.len,
                .by_root_cause = .{0} ** @typeInfo(RootCauseTag).@"enum".fields.len,
            },
        };
    }

    pub fn deinit(self: *DiagnosticEngine) void {
        for (self.diagnostics.items) |*diagnostic| {
            diagnostic.deinit(self.allocator);
        }
        self.diagnostics.deinit(self.allocator);
    }

    /// Add a diagnostic with automatic root cause analysis
    pub fn addDiagnostic(self: *DiagnosticEngine, diagnostic: EnhancedDiagnostic) !void {
        // Check if category is suppressed
        for (self.thresholds.suppressed_categories) |suppressed| {
            if (suppressed == diagnostic.category) {
                return;
            }
        }

        // Check if code is suppressed
        for (self.thresholds.suppressed_codes) |suppressed_code| {
            if (std.mem.eql(u8, suppressed_code, diagnostic.code)) {
                return;
            }
        }

        // Update statistics
        self.stats.total_diagnostics += 1;
        self.stats.by_severity[@intFromEnum(diagnostic.severity)] += 1;
        self.stats.by_category[@intFromEnum(diagnostic.category)] += 1;
        self.stats.by_root_cause[@intFromEnum(diagnostic.root_cause)] += 1;

        try self.diagnostics.append(self.allocator, diagnostic);

        // Check thresholds
        try self.checkThresholds();
    }

    /// Create unresolved reference diagnostic with root cause analysis
    pub fn createUnresolvedRefDiagnostic(self: *DiagnosticEngine, symbol_ref: []const u8, context: struct {
        file: ?[]const u8 = null,
        line: ?u32 = null,
        plugin: ?[]const u8 = null,
        available_symbols: []const []const u8 = &[_][]const u8{},
    }) !void {
        const root_cause = self.analyzeUnresolvedReference(symbol_ref, context.available_symbols);

        const diag_id = try std.fmt.allocPrint(self.allocator, "unref_{d}", .{self.stats.total_diagnostics});
        const message = try std.fmt.allocPrint(self.allocator, "Unresolved reference: {s}", .{symbol_ref});
        const code_copy = try self.allocator.dupe(u8, "UNRESOLVED_REFERENCE");

        var suggestions = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
        defer suggestions.deinit(self.allocator);

        // Generate suggestions based on root cause
        try generateSuggestionsForUnresolved(self.allocator, &suggestions, symbol_ref, root_cause, context.available_symbols);

        var evidence = DiagnosticEvidence{
            .files = &[_][]const u8{},
            .lines = &[_]u32{},
            .code_snippets = &[_][]const u8{},
            .node_ids = &[_][]const u8{},
        };

        if (context.file) |file| {
            evidence.files = try self.allocator.dupe([]const u8, &[_][]const u8{file});
        }
        if (context.line) |line| {
            evidence.lines = try self.allocator.dupe(u32, &[_]u32{line});
        }

        const diagnostic = EnhancedDiagnostic{
            .id = diag_id,
            .severity = .Warn,
            .category = .Resolution,
            .code = code_copy,
            .message = message,
            .file = if (context.file) |file| try self.allocator.dupe(u8, file) else null,
            .range = null,
            .plugin = if (context.plugin) |plugin| try self.allocator.dupe(u8, plugin) else null,
            .root_cause = root_cause,
            .suggestions = try suggestions.toOwnedSlice(self.allocator),
            .related_symbols = &[_][]const u8{},
            .evidence = evidence,
        };

        try self.addDiagnostic(diagnostic);
    }

    /// Analyze root cause of unresolved reference
    fn analyzeUnresolvedReference(self: *DiagnosticEngine, symbol_ref: []const u8, available_symbols: []const []const u8) RootCauseTag {
        _ = self;

        // Check for similar symbols (typo detection)
        for (available_symbols) |symbol| {
            if (calculateSimilarity(symbol_ref, symbol) > 0.8) {
                return .SymbolNotFound; // Likely a typo
            }
        }

        // Check if it looks like a module path
        if (std.mem.indexOf(u8, symbol_ref, "/") != null or std.mem.indexOf(u8, symbol_ref, ".") != null) {
            return .ModuleNotFound;
        }

        // Check if it starts with uppercase (likely a type)
        if (symbol_ref.len > 0 and std.ascii.isUpper(symbol_ref[0])) {
            return .TypeMismatch;
        }

        return .SymbolNotFound;
    }

    /// Calculate string similarity (Levenshtein distance ratio)
    fn calculateSimilarity(a: []const u8, b: []const u8) f32 {
        if (a.len == 0 and b.len == 0) return 1.0;
        if (a.len == 0 or b.len == 0) return 0.0;

        // Simple character-based similarity for now
        var common: u32 = 0;
        const min_len = @min(a.len, b.len);

        for (0..min_len) |i| {
            if (a[i] == b[i]) common += 1;
        }

        return @as(f32, @floatFromInt(common)) / @as(f32, @floatFromInt(@max(a.len, b.len)));
    }

    /// Generate suggestions for unresolved references
    fn generateSuggestionsForUnresolved(allocator: std.mem.Allocator, suggestions: *std.ArrayList([]const u8), symbol_ref: []const u8, root_cause: RootCauseTag, available_symbols: []const []const u8) !void {
        switch (root_cause) {
            .SymbolNotFound => {
                // Suggest similar symbols
                var best_match: ?[]const u8 = null;
                var best_score: f32 = 0.0;

                for (available_symbols) |symbol| {
                    const score = calculateSimilarity(symbol_ref, symbol);
                    if (score > best_score and score > 0.6) {
                        best_score = score;
                        best_match = symbol;
                    }
                }

                if (best_match) |match| {
                    try suggestions.append(allocator, try std.fmt.allocPrint(allocator, "Did you mean '{s}'?", .{match}));
                }
            },
            .ModuleNotFound => {
                try suggestions.append(allocator, try std.fmt.allocPrint(allocator, "Check if module '{s}' exists and is accessible", .{symbol_ref}));
                try suggestions.append(allocator, try allocator.dupe(u8, "Verify import paths and module structure"));
            },
            .TypeMismatch => {
                try suggestions.append(allocator, try std.fmt.allocPrint(allocator, "Ensure type '{s}' is imported or defined", .{symbol_ref}));
                try suggestions.append(allocator, try allocator.dupe(u8, "Check type visibility and export statements"));
            },
            else => {
                try suggestions.append(allocator, try std.fmt.allocPrint(allocator, "Verify symbol '{s}' exists and is accessible", .{symbol_ref}));
            },
        }
    }

    /// Check if thresholds are exceeded
    fn checkThresholds(self: *DiagnosticEngine) !void {
        const error_count = self.stats.by_severity[@intFromEnum(ir.Severity.Error)];
        const warn_count = self.stats.by_severity[@intFromEnum(ir.Severity.Warn)];

        if (error_count >= self.thresholds.max_errors) {
            try diag.printError("Error threshold exceeded: {d} errors (max {d})", .{ error_count, self.thresholds.max_errors });
            return DiagnosticError.TooManyErrors;
        }

        if (warn_count >= self.thresholds.max_warnings) {
            try diag.printError("Warning threshold exceeded: {d} warnings (max {d})", .{ warn_count, self.thresholds.max_warnings });
            return DiagnosticError.TooManyWarnings;
        }
    }

    /// Get diagnostics by severity
    pub fn getDiagnosticsBySeverity(self: *const DiagnosticEngine, severity: ir.Severity) ![]const EnhancedDiagnostic {
        var filtered = try std.ArrayList(EnhancedDiagnostic).initCapacity(self.allocator, 0);
        defer filtered.deinit(self.allocator);

        for (self.diagnostics.items) |diagnostic| {
            if (diagnostic.severity == severity) {
                try filtered.append(self.allocator, diagnostic);
            }
        }

        return filtered.toOwnedSlice(self.allocator);
    }

    /// Get diagnostics by category
    pub fn getDiagnosticsByCategory(self: *const DiagnosticEngine, category: DiagnosticCategory) ![]const EnhancedDiagnostic {
        var filtered = try std.ArrayList(EnhancedDiagnostic).initCapacity(self.allocator, 0);
        defer filtered.deinit(self.allocator);

        for (self.diagnostics.items) |diagnostic| {
            if (diagnostic.category == category) {
                try filtered.append(self.allocator, diagnostic);
            }
        }

        return filtered.toOwnedSlice(self.allocator);
    }

    /// Get all diagnostics
    pub fn getAllDiagnostics(self: *const DiagnosticEngine) []const EnhancedDiagnostic {
        return self.diagnostics.items;
    }

    /// Get diagnostic statistics
    pub fn getStats(self: *const DiagnosticEngine) struct {
        total_diagnostics: u32,
        errors: u32,
        warnings: u32,
        info: u32,
        resolution_issues: u32,
        unresolved_refs: u32,
    } {
        return .{
            .total_diagnostics = self.stats.total_diagnostics,
            .errors = self.stats.by_severity[@intFromEnum(ir.Severity.Error)],
            .warnings = self.stats.by_severity[@intFromEnum(ir.Severity.Warn)],
            .info = self.stats.by_severity[@intFromEnum(ir.Severity.Info)],
            .resolution_issues = self.stats.by_category[@intFromEnum(DiagnosticCategory.Resolution)],
            .unresolved_refs = self.stats.by_root_cause[@intFromEnum(RootCauseTag.SymbolNotFound)],
        };
    }

    /// Convert enhanced diagnostics to basic IR diagnostics
    pub fn toIRDiagnostics(self: *const DiagnosticEngine) ![]ir.FullDiagnostic {
        var ir_diagnostics = try self.allocator.alloc(ir.FullDiagnostic, self.diagnostics.items.len);

        for (self.diagnostics.items, 0..) |enhanced, i| {
            ir_diagnostics[i] = .{
                .id = try self.allocator.dupe(u8, enhanced.id),
                .severity = enhanced.severity,
                .code = try self.allocator.dupe(u8, enhanced.code),
                .message = try self.allocator.dupe(u8, enhanced.message),
                .file = if (enhanced.file) |file| try self.allocator.dupe(u8, file) else null,
                .range = enhanced.range,
                .plugin = if (enhanced.plugin) |plugin| try self.allocator.dupe(u8, plugin) else null,
            };
        }

        return ir_diagnostics;
    }

    /// Free IR diagnostics allocated by toIRDiagnostics
    pub fn freeIRDiagnostics(self: *const DiagnosticEngine, ir_diagnostics: []ir.FullDiagnostic) void {
        for (ir_diagnostics) |*diagnostic_item| {
            self.allocator.free(diagnostic_item.id);
            self.allocator.free(diagnostic_item.code);
            self.allocator.free(diagnostic_item.message);
            if (diagnostic_item.file) |file| {
                self.allocator.free(file);
            }
            if (diagnostic_item.plugin) |plugin| {
                self.allocator.free(plugin);
            }
        }
        self.allocator.free(ir_diagnostics);
    }

    /// Context for unresolved reference analysis
    const UnresolvedContext = struct {
        available_symbols: []const []const u8,
        source_lang: ?[]const u8,
        target_lang: ?[]const u8,
        edge_type: ?[]const u8,
    };

    /// Create unresolved reference diagnostic from resolver context
    pub fn createFromResolverContext(self: *DiagnosticEngine, symbol_ref: []const u8, context: struct {
        file: ?[]const u8 = null,
        line: ?u32 = null,
        plugin: ?[]const u8 = null,
        available_symbols: []const []const u8 = &[_][]const u8{},
        edge_type: ?[]const u8 = null,
        source_lang: ?[]const u8 = null,
        target_lang: ?[]const u8 = null,
    }) !void {
        const analysis_context = UnresolvedContext{
            .available_symbols = context.available_symbols,
            .source_lang = context.source_lang,
            .target_lang = context.target_lang,
            .edge_type = context.edge_type,
        };
        const root_cause = self.analyzeUnresolvedReferenceWithContext(symbol_ref, analysis_context);

        const diag_id = try std.fmt.allocPrint(self.allocator, "unref_{d}", .{self.stats.total_diagnostics});
        const message = try std.fmt.allocPrint(self.allocator, "Unresolved reference: {s} ({s})", .{ symbol_ref, @tagName(root_cause) });
        const code_copy = try self.allocator.dupe(u8, "UNRESOLVED_REFERENCE");

        var suggestions = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
        defer suggestions.deinit(self.allocator);

        // TODO: Generate suggestions based on root cause and context
        // try generateSuggestionsWithContext(self.allocator, &suggestions, symbol_ref, root_cause, context);

        var evidence = DiagnosticEvidence{
            .files = &[_][]const u8{},
            .lines = &[_]u32{},
            .code_snippets = &[_][]const u8{},
            .node_ids = &[_][]const u8{},
        };

        if (context.file) |file| {
            evidence.files = try self.allocator.dupe([]const u8, &[_][]const u8{file});
        }
        if (context.line) |line| {
            evidence.lines = try self.allocator.dupe(u32, &[_]u32{line});
        }

        const diagnostic = EnhancedDiagnostic{
            .id = diag_id,
            .severity = .Warn,
            .category = .Resolution,
            .code = code_copy,
            .message = message,
            .file = if (context.file) |file| try self.allocator.dupe(u8, file) else null,
            .range = null,
            .plugin = if (context.plugin) |plugin| try self.allocator.dupe(u8, plugin) else null,
            .root_cause = root_cause,
            .suggestions = try suggestions.toOwnedSlice(self.allocator),
            .related_symbols = &[_][]const u8{},
            .evidence = evidence,
        };

        try self.addDiagnostic(diagnostic);
    }

    /// Enhanced root cause analysis with context
    fn analyzeUnresolvedReferenceWithContext(self: *DiagnosticEngine, symbol_ref: []const u8, context: UnresolvedContext) RootCauseTag {
        _ = self;

        // Cross-language resolution failure
        if (context.source_lang) |src_lang| {
            if (context.target_lang) |tgt_lang| {
                if (!std.mem.eql(u8, src_lang, tgt_lang)) {
                    return .CrossLanguage;
                }
            }
        }

        // Check for similar symbols (typo detection)
        for (context.available_symbols) |symbol| {
            if (calculateSimilarity(symbol_ref, symbol) > 0.8) {
                return .SymbolNotFound; // Likely a typo
            }
        }

        // Check if it looks like a module path
        if (std.mem.indexOf(u8, symbol_ref, "/") != null or std.mem.indexOf(u8, symbol_ref, ".") != null) {
            return .ModuleNotFound;
        }

        // Check if it starts with uppercase (likely a type)
        if (symbol_ref.len > 0 and std.ascii.isUpper(symbol_ref[0])) {
            return .TypeMismatch;
        }

        // Check for C-specific patterns
        if (std.mem.endsWith(u8, symbol_ref, "_t") or
            std.mem.startsWith(u8, symbol_ref, "struct_") or
            std.mem.startsWith(u8, symbol_ref, "enum_"))
        {
            return .TypeMismatch;
        }

        return .SymbolNotFound;
    }

    /// Generate suggestions with full context
    fn generateSuggestionsWithContext(allocator: std.mem.Allocator, suggestions: *std.ArrayList([]const u8), symbol_ref: []const u8, root_cause: RootCauseTag, context: struct {
        available_symbols: []const []const u8,
        source_lang: ?[]const u8,
        target_lang: ?[]const u8,
        edge_type: ?[]const u8,
    }) !void {
        switch (root_cause) {
            .CrossLanguage => {
                if (context.source_lang) |src_lang| {
                    if (context.target_lang) |tgt_lang| {
                        try suggestions.append(allocator, try std.fmt.allocPrint(allocator, "Cross-language reference from {s} to {s} failed", .{ src_lang, tgt_lang }));
                        try suggestions.append(allocator, try std.fmt.allocPrint(allocator, "Check if symbol '{s}' is properly exported from {s} module", .{ symbol_ref, tgt_lang }));
                    }
                }
            },
            .SymbolNotFound => {
                // Suggest similar symbols
                var best_match: ?[]const u8 = null;
                var best_score: f32 = 0.0;

                for (context.available_symbols) |symbol| {
                    const score = calculateSimilarity(symbol_ref, symbol);
                    if (score > best_score and score > 0.6) {
                        best_score = score;
                        best_match = symbol;
                    }
                }

                if (best_match) |match| {
                    try suggestions.append(allocator, try std.fmt.allocPrint(allocator, "Did you mean '{s}'?", .{match}));
                }
            },
            .ModuleNotFound => {
                try suggestions.append(allocator, try std.fmt.allocPrint(allocator, "Check if module '{s}' exists and is accessible", .{symbol_ref}));
                try suggestions.append(allocator, try allocator.dupe(u8, "Verify import paths and module structure"));
            },
            .TypeMismatch => {
                try suggestions.append(allocator, try std.fmt.allocPrint(allocator, "Ensure type '{s}' is imported or defined", .{symbol_ref}));
                try suggestions.append(allocator, try allocator.dupe(u8, "Check type visibility and export statements"));
            },
            else => {
                try suggestions.append(allocator, try std.fmt.allocPrint(allocator, "Verify symbol '{s}' exists and is accessible", .{symbol_ref}));
            },
        }
    }
};

// Error types for diagnostic thresholds
const DiagnosticError = error{
    TooManyErrors,
    TooManyWarnings,
    OutOfMemory,
};
