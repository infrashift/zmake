//! Core data types of zmake: syntax modes, target kinds, variables, rules and the
//! parsed input file. The parser emits statements in file order. The evaluator
//! replays them, so immediate expansion sees only the variables defined so far.

const std = @import("std");
const assert = std.debug.assert;

/// Hard limits (ADR-0003, rule R3). An input that exceeds a limit fails with an error.
pub const limits = struct {
    pub const input_file_bytes_max: usize = 16 * 1024 * 1024;
    pub const input_lines_max: u32 = 1_000_000;
    pub const expansion_depth_max: u32 = 64;
    pub const expansion_bytes_max: usize = 4 * 1024 * 1024;
    pub const expansion_steps_max: u32 = 10_000_000;
    pub const graph_nodes_max: u32 = 65_536;
    pub const graph_depth_max: u32 = 1024;
    pub const jobs_max: u32 = 256;
    pub const recipe_lines_max: u32 = 4096;
    pub const names_per_line_max: u32 = 65_536;
    /// Arguments of one function call, for example `$(call f,a,b)`.
    pub const function_args_max: u8 = 16;
    /// Nested conditionals (`ifeq` inside `ifeq`).
    pub const conditional_depth_max: u32 = 256;
    /// Open sources: the input file, included files and `$(eval)` texts.
    pub const source_depth_max: u32 = 64;
    /// Logical lines that one invocation reads, over all sources.
    pub const read_lines_max: u32 = 4_000_000;
};

pub const SyntaxMode = enum {
    /// Strict POSIX and GNU Make semantics.
    legacy,
    /// ZMakefile semantics: tasks, phony inference, space-indented recipes.
    modern,
};

pub const TargetKind = enum {
    /// A file on disk. zmake compares modification times.
    file,
    /// Named in `.PHONY`, or declared as a task in modern mode. Always runs.
    explicit_phony,
    /// Modern mode: a bare name with no `$@` in its recipe. Always runs.
    inferred_phony,

    pub fn isPhony(kind: TargetKind) bool {
        return switch (kind) {
            .file => false,
            .explicit_phony, .inferred_phony => true,
        };
    }
};

/// The assignment operator of a variable definition.
pub const VariableFlavor = enum {
    /// `:=` or `::=`: expand the value once, at definition time.
    simple,
    /// `=`: expand the value each time zmake uses it.
    recursive,
    /// `?=`: define a recursive variable only when it has no definition.
    conditional,
    /// `+=`: append to the value. Keep the flavor of the existing variable.
    append,
};

/// Where a variable definition comes from. A higher value wins.
pub const Origin = enum(u8) {
    /// Built-in values such as `MAKE` and `SHELL`.
    default = 0,
    environment = 1,
    file = 2,
    command_line = 3,
    /// An `override` assignment in the input file. It wins over the command line.
    override = 4,
    /// The variables of `foreach`, `let` and `call`. They shadow other definitions.
    automatic = 5,

    /// The name that `$(origin ...)` returns.
    pub fn text(origin: Origin) []const u8 {
        return switch (origin) {
            .default => "default",
            .environment => "environment",
            .file => "file",
            .command_line => "command line",
            .override => "override",
            .automatic => "automatic",
        };
    }
};

pub const Variable = struct {
    value: []const u8,
    /// True for `=` and `?=` variables: expand at each use.
    recursive: bool,
    origin: Origin,
    /// A target-specific `private` variable: prerequisites do not inherit it.
    private: bool = false,
    /// A target-specific `export` variable: the recipe environment gets it.
    exported: bool = false,
};

pub const RecipeLine = struct {
    /// The command text with the leading tab or modern indent removed.
    text: []const u8,
    /// Prefixed with `@`: do not echo the line.
    silent: bool,
    /// Prefixed with `-`: ignore a non-zero exit code.
    ignore_error: bool,
    /// Prefixed with `+`: run the line also under `-n`.
    always_run: bool,
    line: u32,
};

pub const Assignment = struct {
    name: []const u8,
    flavor: VariableFlavor,
    /// The unexpanded value text.
    value: []const u8,
    line: u32,
    /// Declared with `override`: the assignment wins over the command line.
    override: bool = false,
};

/// A rule as the parser reads it. Target and prerequisite text is unexpanded.
pub const RuleDecl = struct {
    targets: []const u8,
    prerequisites: []const u8,
    order_only: []const u8,
    recipes: []const RecipeLine,
    /// True when the rule has a recipe, also an empty `;` recipe.
    has_recipe: bool,
    /// Modern mode: declared with `@name:` or `task name:`.
    task: bool,
    line: u32,
    /// The input file of the rule, for messages. Included files have their own.
    file: []const u8 = "",
    /// `target:: prerequisites`: an independent rule for the target.
    double_colon: bool = false,
    /// `targets: target-pattern: prerequisite-patterns`: the unexpanded target
    /// pattern of a static pattern rule, else null.
    target_pattern: ?[]const u8 = null,
};

/// A line with no separator, for example `$(info text)`. The loader expands it.
/// GNU Make accepts the line when the expansion is empty.
pub const Expression = struct {
    text: []const u8,
    line: u32,
};

/// `targets: [override] [export] [private] NAME op value`. The value is in
/// effect for the recipes of the targets and of the prerequisites they build.
pub const TargetVar = struct {
    targets: []const u8,
    assignment: Assignment,
    exported: bool,
    private: bool,
};

pub const Statement = union(enum) {
    assignment: Assignment,
    rule: RuleDecl,
    expression: Expression,
    target_var: TargetVar,
};

/// The parsed input file.
pub const Makefile = struct {
    mode: SyntaxMode,
    filename: []const u8,
    statements: []const Statement,
};

/// A rule after the evaluator expands its targets and prerequisites.
pub const Rule = struct {
    targets: []const []const u8,
    prerequisites: []const []const u8,
    order_only: []const []const u8,
    recipes: []const RecipeLine,
    has_recipe: bool,
    task: bool,
    is_pattern: bool,
    source_line: u32,
    file: []const u8 = "",
    double_colon: bool = false,
    /// The stem of the target of a static pattern rule (`$*`), else null.
    stem: ?[]const u8 = null,
};

/// True when `name` contains a `%` stem marker.
pub fn isPattern(name: []const u8) bool {
    assert(name.len > 0);
    return std.mem.indexOfScalar(u8, name, '%') != null;
}

/// True for special targets such as `.PHONY` and `.DEFAULT_GOAL`.
pub fn isSpecialTarget(name: []const u8) bool {
    assert(name.len > 0);
    if (name[0] != '.' or name.len < 2) return false;
    for (name[1..]) |c| {
        if (!std.ascii.isUpper(c) and c != '_') return false;
    }
    assert(name[0] == '.' and !isPattern(name));
    return true;
}

test "target kind phony predicate" {
    try std.testing.expect(!TargetKind.file.isPhony());
    try std.testing.expect(TargetKind.explicit_phony.isPhony());
    try std.testing.expect(TargetKind.inferred_phony.isPhony());
}

test "origin precedence order" {
    try std.testing.expect(@backingInt(Origin.command_line) > @backingInt(Origin.file));
    try std.testing.expect(@backingInt(Origin.file) > @backingInt(Origin.environment));
}

test "pattern and special target names" {
    try std.testing.expect(isPattern("%.o"));
    try std.testing.expect(!isPattern("main.o"));
    try std.testing.expect(isSpecialTarget(".PHONY"));
    try std.testing.expect(isSpecialTarget(".DEFAULT_GOAL"));
    try std.testing.expect(!isSpecialTarget(".o"));
    try std.testing.expect(!isSpecialTarget("all"));
}

test "rule construction" {
    const recipe = [_]RecipeLine{.{
        .text = "cc -c $<",
        .silent = false,
        .ignore_error = false,
        .always_run = false,
        .line = 2,
    }};
    const rule: Rule = .{
        .targets = &.{"main.o"},
        .prerequisites = &.{"main.c"},
        .order_only = &.{},
        .recipes = &recipe,
        .has_recipe = true,
        .task = false,
        .is_pattern = false,
        .source_line = 1,
    };
    try std.testing.expectEqual(@as(usize, 1), rule.recipes.len);
    try std.testing.expectEqualStrings("main.c", rule.prerequisites[0]);
}
