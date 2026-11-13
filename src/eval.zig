//! Two-phase variable evaluator.
//!
//! - `load` replays the statements of the input file in order. It expands `:=`
//!   values, target names and prerequisite lists at once (immediate phase).
//! - `expand` expands `=` values and recipe lines on demand (deferred phase).
//!
//! Make expansion nests: a value can refer to a variable whose value refers to
//! another variable. ADR-0003 forbids recursion, so `expand` keeps an explicit
//! stack of frames. Each frame expands one string. A frame that waits for the
//! arguments of a reference or a function has a `pending` call and a child frame
//! above it. When a child frame ends, `deliver` hands its result to the parent.

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const ast = @import("ast.zig");
const fns = @import("functions.zig");
const textfns = @import("textfns.zig");
const builtins = @import("builtins.zig");
const parser = @import("parser.zig");
const Diagnostic = @import("diag.zig").Diagnostic;

pub const Error = error{ Eval, OutOfMemory };

/// The automatic variables of one recipe.
pub const Auto = struct {
    target: []const u8,
    /// All prerequisites in order, with duplicates (`$+`).
    prerequisites: []const []const u8,
    stem: []const u8,
    /// The prerequisites newer than the target (`$?`).
    newer: []const []const u8,
};

pub const VarTable = std.StringHashMapUnmanaged(ast.Variable);

/// The built-in functions, plus `ref` (a variable reference) and `subst_ref`
/// (a substitution reference such as `$(SRC:.c=.o)`).
pub const Func = enum {
    ref,
    subst_ref,
    subst,
    patsubst,
    wildcard,
    shell,
    filter,
    filter_out,
    findstring,
    sort,
    strip,
    word,
    words,
    wordlist,
    firstword,
    lastword,
    dir,
    notdir,
    suffix,
    basename,
    addsuffix,
    addprefix,
    join,
    abspath,
    realpath,
    value,
    origin,
    flavor,
    @"error",
    warning,
    info,
    file,
    @"if",
    @"and",
    @"or",
    intcmp,
    foreach,
    let,
    call,
    eval,
};

/// A built-in function and its argument counts. `max == 0` means no upper
/// limit. A function with a fixed maximum keeps extra commas in its last argument.
pub const Spec = struct { name: []const u8, func: Func, min: u8, max: u8 };

pub const specs = [_]Spec{
    .{ .name = "subst", .func = .subst, .min = 3, .max = 3 },
    .{ .name = "patsubst", .func = .patsubst, .min = 3, .max = 3 },
    .{ .name = "wildcard", .func = .wildcard, .min = 1, .max = 1 },
    .{ .name = "shell", .func = .shell, .min = 1, .max = 1 },
    .{ .name = "filter", .func = .filter, .min = 2, .max = 2 },
    .{ .name = "filter-out", .func = .filter_out, .min = 2, .max = 2 },
    .{ .name = "findstring", .func = .findstring, .min = 2, .max = 2 },
    .{ .name = "sort", .func = .sort, .min = 1, .max = 1 },
    .{ .name = "strip", .func = .strip, .min = 1, .max = 1 },
    .{ .name = "word", .func = .word, .min = 2, .max = 2 },
    .{ .name = "words", .func = .words, .min = 1, .max = 1 },
    .{ .name = "wordlist", .func = .wordlist, .min = 3, .max = 3 },
    .{ .name = "firstword", .func = .firstword, .min = 1, .max = 1 },
    .{ .name = "lastword", .func = .lastword, .min = 1, .max = 1 },
    .{ .name = "dir", .func = .dir, .min = 1, .max = 1 },
    .{ .name = "notdir", .func = .notdir, .min = 1, .max = 1 },
    .{ .name = "suffix", .func = .suffix, .min = 1, .max = 1 },
    .{ .name = "basename", .func = .basename, .min = 1, .max = 1 },
    .{ .name = "addsuffix", .func = .addsuffix, .min = 2, .max = 2 },
    .{ .name = "addprefix", .func = .addprefix, .min = 2, .max = 2 },
    .{ .name = "join", .func = .join, .min = 2, .max = 2 },
    .{ .name = "abspath", .func = .abspath, .min = 1, .max = 1 },
    .{ .name = "realpath", .func = .realpath, .min = 1, .max = 1 },
    .{ .name = "value", .func = .value, .min = 1, .max = 1 },
    .{ .name = "origin", .func = .origin, .min = 1, .max = 1 },
    .{ .name = "flavor", .func = .flavor, .min = 1, .max = 1 },
    .{ .name = "error", .func = .@"error", .min = 1, .max = 1 },
    .{ .name = "warning", .func = .warning, .min = 1, .max = 1 },
    .{ .name = "info", .func = .info, .min = 1, .max = 1 },
    .{ .name = "file", .func = .file, .min = 1, .max = 2 },
    .{ .name = "if", .func = .@"if", .min = 2, .max = 3 },
    .{ .name = "and", .func = .@"and", .min = 1, .max = 0 },
    .{ .name = "or", .func = .@"or", .min = 1, .max = 0 },
    .{ .name = "intcmp", .func = .intcmp, .min = 2, .max = 5 },
    .{ .name = "foreach", .func = .foreach, .min = 3, .max = 3 },
    .{ .name = "let", .func = .let, .min = 3, .max = 3 },
    .{ .name = "call", .func = .call, .min = 1, .max = 0 },
    .{ .name = "eval", .func = .eval, .min = 1, .max = 1 },
};

pub fn findSpec(name: []const u8) ?Spec {
    assert(name.len > 0);
    for (specs) |s| {
        if (std.mem.eql(u8, s.name, name)) return s;
    }
    assert(specs.len > 0);
    return null;
}

const args_max = ast.limits.function_args_max;
const ws = fns.whitespace;

/// The names `$(0)` to `$(15)` that `call` binds.
const param_names = blk: {
    var names: [args_max][]const u8 = undefined;
    for (&names, 0..) |*n, i| n.* = std.fmt.comptimePrint("{d}", .{i});
    break :blk names;
};

/// `args`: the frame expands the arguments one by one. `body`: the frame
/// expands the chosen branch of `if` or `intcmp`, or the body of `foreach`,
/// `let` or `call`.
const Stage = enum { args, body };

/// The variables that `foreach`, `let` or `call` bind while the body expands.
/// `saved` holds the definitions that the bindings shadow.
const Scope = struct {
    names: []const []const u8,
    saved: []?ast.Variable,
    words: []const []const u8 = &.{},
    index: usize = 0,
    out: std.ArrayList(u8) = .empty,
};

const Pending = struct {
    func: Func,
    n: u8 = 0,
    next: u8 = 0,
    stage: Stage = .args,
    raw: [args_max][]const u8 = @splat(""),
    results: [args_max][]const u8 = @splat(""),
    scope: ?*Scope = null,
};

const Frame = struct {
    src: []const u8,
    pos: usize = 0,
    out: std.ArrayList(u8) = .empty,
    pending: ?Pending = null,
    /// Set when the frame expands the value of a recursive variable.
    var_name: ?[]const u8 = null,
    /// A substitution reference (`$(X:a=b)`) to apply to the result.
    subst: ?[2][]const u8 = null,
};

const Stack = struct {
    frames: [ast.limits.expansion_depth_max]Frame = undefined,
    len: usize = 0,

    fn top(s: *Stack) *Frame {
        assert(s.len > 0 and s.len <= s.frames.len);
        const f = &s.frames[s.len - 1];
        assert(f.pos <= f.src.len);
        return f;
    }
};

/// GNU Make functions that zmake does not implement (ADR-0005). zmake rejects
/// them, so such a reference does not expand to an empty variable by mistake.
const unsupported_functions = [_][]const u8{"guile"};

pub const Evaluator = struct {
    arena: std.mem.Allocator,
    io: Io,
    /// The directory for `$(wildcard ...)`.
    dir: Io.Dir,
    diag: *Diagnostic,
    vars: VarTable = .empty,
    /// The location for error messages.
    filename: []const u8 = "zmake",
    line: u32 = 0,
    /// The absolute working directory for `$(abspath ...)`, read once.
    cwd: ?[]const u8 = null,
    /// True while the reader reads the input files. `$(eval)` works only then.
    reading: bool = false,
    /// The texts of `$(eval ...)` calls. The reader reads them after the statement.
    eval_queue: std.ArrayList([]const u8) = .empty,
    /// `export NAME` (true) and `unexport NAME` (false). See `exported`.
    export_flags: std.StringHashMapUnmanaged(bool) = .empty,
    /// `export` with no names, or `.EXPORT_ALL_VARIABLES`.
    export_all: bool = false,

    pub fn init(arena: std.mem.Allocator, io: Io, dir: Io.Dir, diag: *Diagnostic) Evaluator {
        assert(diag.len <= Diagnostic.capacity);
        const ev: Evaluator = .{ .arena = arena, .io = io, .dir = dir, .diag = diag };
        assert(ev.vars.count() == 0);
        return ev;
    }

    /// Define a variable unless a definition with a higher origin exists.
    pub fn define(ev: *Evaluator, name: []const u8, value: []const u8, recursive: bool, origin: ast.Origin) Error!void {
        assert(name.len > 0);
        if (ev.vars.get(name)) |old| {
            if (@backingInt(old.origin) > @backingInt(origin)) return;
        }
        try ev.vars.put(ev.arena, name, .{ .value = value, .recursive = recursive, .origin = origin });
        assert(ev.vars.contains(name));
    }

    /// `undefine NAME`: remove the variable unless a higher origin defines it.
    pub fn undefine(ev: *Evaluator, name: []const u8, origin: ast.Origin) void {
        assert(name.len > 0);
        const old = ev.vars.get(name) orelse return;
        if (@backingInt(old.origin) > @backingInt(origin)) return;
        const removed = ev.vars.remove(name);
        assert(removed);
    }

    pub fn setExport(ev: *Evaluator, name: []const u8, on: bool) Error!void {
        assert(name.len > 0);
        try ev.export_flags.put(ev.arena, name, on);
        assert(ev.export_flags.get(name).? == on);
    }

    /// True when a recipe gets variable `name` in its environment, as in GNU
    /// Make: an `export` or `unexport` flag decides first. Without a flag, a
    /// variable from the command line or the environment goes, also with a
    /// value that the input file changed. With `export_all`, a file variable
    /// with a valid shell name also goes. `in_env` tells whether the
    /// environment of zmake has the name.
    pub fn exported(ev: *const Evaluator, name: []const u8, v: ast.Variable, in_env: bool) bool {
        assert(name.len > 0);
        if (ev.export_flags.get(name)) |on| return on;
        const managed = [_][]const u8{ "SHELL", "MAKEFLAGS", "MAKELEVEL", "MAKEFILE_LIST" };
        for (managed) |m| {
            if (std.mem.eql(u8, m, name)) return false;
        }
        switch (v.origin) {
            .default, .automatic => return false,
            .command_line => return true,
            .environment, .file, .override => {},
        }
        if (in_env) return true;
        assert(v.origin != .default);
        return ev.export_all and isShellName(name);
    }

    pub fn lookup(ev: *const Evaluator, name: []const u8) ?ast.Variable {
        assert(name.len > 0);
        return ev.vars.get(name);
    }

    /// Set `MAKE` and `SHELL`. GNU Make ignores `SHELL` from the environment.
    pub fn defineDefaults(ev: *Evaluator, make_path: []const u8) Error!void {
        assert(make_path.len > 0);
        try ev.define("MAKE", make_path, false, .default);
        try ev.define("SHELL", "/bin/sh", false, .default);
        assert(ev.vars.count() >= 2);
    }

    /// Import the environment as recursive variables, except `SHELL`.
    pub fn importEnvironment(ev: *Evaluator, env: *const std.process.Environ.Map) Error!void {
        var it = env.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            if (name.len == 0 or std.mem.eql(u8, name, "SHELL")) continue;
            assert(name.len > 0);
            try ev.define(name, entry.value_ptr.*, true, .environment);
        }
        assert(ev.vars.count() >= env.count() -| 1);
    }

    pub fn fail(ev: *Evaluator, comptime fmt: []const u8, args: anytype) Error {
        comptime assert(fmt.len > 0);
        var buf: [Diagnostic.capacity]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch "error";
        if (ev.line > 0) {
            ev.diag.set("{s}:{d}: *** {s}.  Stop.", .{ ev.filename, ev.line, msg });
        } else {
            ev.diag.set("*** {s}.  Stop.", .{msg});
        }
        assert(ev.diag.len > 0);
        return error.Eval;
    }

    /// Expand `text`. `auto` holds the automatic variables of a recipe, or null.
    pub fn expand(ev: *Evaluator, text: []const u8, auto: ?*const Auto) Error![]const u8 {
        if (std.mem.indexOfScalar(u8, text, '$') == null) return text;
        var stack: Stack = .{};
        try ev.push(&stack, .{ .src = text });
        var steps: u32 = 0;
        while (steps < ast.limits.expansion_steps_max) : (steps += 1) {
            assert(stack.len >= 1);
            const top = stack.top();
            assert(top.pending == null);
            if (top.pos < top.src.len) {
                try ev.scan(&stack, auto);
                continue;
            }
            const result = try ev.finish(top);
            stack.len -= 1;
            if (stack.len == 0) {
                assert(result.len <= ast.limits.expansion_bytes_max);
                return result;
            }
            try ev.deliver(&stack, result, auto);
        }
        return ev.fail("expansion takes more than {d} steps", .{ast.limits.expansion_steps_max});
    }

    fn push(ev: *Evaluator, stack: *Stack, frame: Frame) Error!void {
        assert(stack.len <= stack.frames.len);
        if (stack.len == stack.frames.len) {
            return ev.fail("variable references nest more than {d} levels", .{ast.limits.expansion_depth_max});
        }
        stack.frames[stack.len] = frame;
        stack.len += 1;
        assert(stack.top().pos == 0);
    }

    /// End a frame: apply its substitution reference and return the text.
    fn finish(ev: *Evaluator, frame: *Frame) Error![]const u8 {
        assert(frame.pos == frame.src.len and frame.pending == null);
        const sub = frame.subst orelse return frame.out.items;
        const result = try fns.substRef(ev.arena, sub[0], sub[1], frame.out.items);
        assert(frame.var_name != null);
        return result;
    }

    /// Give the result of the frame that ended to its parent, the new top.
    fn deliver(ev: *Evaluator, stack: *Stack, result: []const u8, auto: ?*const Auto) Error!void {
        assert(stack.len >= 1);
        const parent = stack.top();
        if (parent.pending) |*p| {
            if (p.stage == .body) return ev.bodyDone(stack, result);
            assert(p.next < p.n);
            p.results[p.next] = result;
            p.next += 1;
            return ev.advance(stack, auto);
        }
        try ev.emit(parent, result);
        assert(parent.pending == null);
    }

    /// One more argument has a value. Expand the next argument, start a body,
    /// or apply the call. `if`, `and`, `or` and `intcmp` expand only the
    /// arguments that they need.
    fn advance(ev: *Evaluator, stack: *Stack, auto: ?*const Auto) Error!void {
        const p = &stack.top().pending.?;
        assert(p.stage == .args and p.next >= 1 and p.next <= p.n);
        assert(p.n <= args_max);
        switch (p.func) {
            .@"if" => return ev.chooseBranch(stack, if (std.mem.trim(u8, p.results[0], ws).len > 0) 1 else 2),
            .@"and", .@"or" => return ev.advanceLogic(stack),
            .intcmp => if (p.next == 2) return ev.compareInts(stack),
            .foreach, .let => if (p.next == 2) return ev.startLoop(stack),
            else => {},
        }
        if (p.next < p.n) return ev.push(stack, .{ .src = p.raw[p.next] });
        if (p.func == .call) return ev.startCall(stack);
        const done = p.*;
        stack.top().pending = null;
        try ev.complete(stack, done, auto);
    }

    /// End the pending call of the top frame with `text` as its result.
    fn finishPending(ev: *Evaluator, stack: *Stack, text: []const u8) Error!void {
        const top = stack.top();
        assert(top.pending != null);
        top.pending = null;
        try ev.emit(top, text);
        assert(top.pending == null);
    }

    /// Expand argument `index` as the result. A missing argument gives an empty result.
    fn chooseBranch(ev: *Evaluator, stack: *Stack, index: u8) Error!void {
        const p = &stack.top().pending.?;
        assert(p.stage == .args and index >= 1);
        if (index >= p.n) return ev.finishPending(stack, "");
        p.stage = .body;
        try ev.push(stack, .{ .src = p.raw[index] });
        assert(stack.len >= 2);
    }

    /// `and` stops at the first empty argument. `or` stops at the first non-empty one.
    fn advanceLogic(ev: *Evaluator, stack: *Stack) Error!void {
        const p = &stack.top().pending.?;
        assert(p.func == .@"and" or p.func == .@"or");
        assert(p.next >= 1 and p.next <= p.n);
        const last = p.results[p.next - 1];
        const is_and = p.func == .@"and";
        const empty = std.mem.trim(u8, last, ws).len == 0;
        if (is_and and empty) return ev.finishPending(stack, "");
        if (!is_and and !empty) return ev.finishPending(stack, last);
        if (p.next < p.n) return ev.push(stack, .{ .src = p.raw[p.next] });
        try ev.finishPending(stack, if (is_and) last else "");
    }

    /// `$(intcmp lhs,rhs[,lt[,eq[,gt]]])`. A missing `gt` part is the `eq` part.
    /// With two arguments, the result is the number when both are equal.
    fn compareInts(ev: *Evaluator, stack: *Stack) Error!void {
        const p = &stack.top().pending.?;
        assert(p.func == .intcmp and p.next == 2);
        const lhs = try ev.parseInt("first", "intcmp", p.results[0]);
        const rhs = try ev.parseInt("second", "intcmp", p.results[1]);
        if (p.n == 2) {
            const text = if (lhs == rhs) try std.fmt.allocPrint(ev.arena, "{d}", .{lhs}) else "";
            return ev.finishPending(stack, text);
        }
        const index: u8 = switch (std.math.order(lhs, rhs)) {
            .lt => 2,
            .eq => 3,
            .gt => if (p.n > 4) 4 else 3,
        };
        assert(index >= 2 and index <= 4);
        try ev.chooseBranch(stack, index);
    }

    /// Parse a decimal integer argument. `which` is "first" or "second".
    pub fn parseInt(ev: *Evaluator, which: []const u8, func: []const u8, text: []const u8) Error!i64 {
        assert(which.len > 0 and func.len > 0);
        const t = std.mem.trim(u8, text, ws);
        assert(t.len <= text.len);
        return std.fmt.parseInt(i64, t, 10) catch return ev.fail("non-numeric {s} argument to '{s}' function: '{s}'", .{ which, func, t });
    }

    /// Bind the variable of `foreach` or the variables of `let`, then expand the body.
    fn startLoop(ev: *Evaluator, stack: *Stack) Error!void {
        const p = &stack.top().pending.?;
        assert(p.next == 2 and p.n == 3);
        const words = try fns.splitWords(ev.arena, p.results[1]);
        if (p.func == .foreach and words.len == 0) return ev.finishPending(stack, "");
        const name = std.mem.trim(u8, p.results[0], ws);
        const names: []const []const u8 = if (p.func == .let)
            try fns.splitWords(ev.arena, name)
        else if (name.len > 0) try ev.arena.dupe([]const u8, &.{name}) else &.{};
        const scope = try ev.openScope(names);
        scope.words = words;
        if (p.func == .let) {
            try ev.bindLet(scope);
        } else if (names.len > 0) {
            try ev.setAutomatic(names[0], words[0]);
        }
        p.scope = scope;
        p.stage = .body;
        assert(p.func == .foreach or p.func == .let);
        try ev.push(stack, .{ .src = p.raw[2] });
    }

    /// `let`: each name takes one word. The last name takes the rest of the list.
    fn bindLet(ev: *Evaluator, scope: *const Scope) Error!void {
        assert(scope.saved.len == scope.names.len);
        if (scope.names.len == 0) return;
        const last = scope.names.len - 1;
        for (scope.names, 0..) |name, i| {
            const value = if (i < last)
                (if (i < scope.words.len) scope.words[i] else "")
            else if (last < scope.words.len) try joinWords(ev.arena, scope.words[last..], false) else "";
            try ev.setAutomatic(name, value);
        }
        assert(ev.vars.contains(scope.names[last]));
    }

    /// `call`: bind `$(0)` to `$(15)`, then expand the value of the variable.
    /// A simple variable gives its value as it is, as in GNU Make. A built-in
    /// function name calls the function with the arguments.
    fn startCall(ev: *Evaluator, stack: *Stack) Error!void {
        const p = &stack.top().pending.?;
        assert(p.func == .call and p.next == p.n);
        const name = std.mem.trim(u8, p.results[0], ws);
        if (name.len == 0) return ev.finishPending(stack, "");
        if (findSpec(name) != null) {
            const args = try textfns.escapeDollars(ev.arena, p.results[1..p.n]);
            p.stage = .body;
            return ev.push(stack, .{ .src = try std.mem.concat(ev.arena, u8, &.{ "$(", name, " ", args, ")" }) });
        }
        const v = ev.lookup(name) orelse return ev.finishPending(stack, "");
        const scope = try ev.openScope(&param_names);
        for (param_names, 0..) |param, i| {
            try ev.setAutomatic(param, if (i == 0) name else if (i < p.n) p.results[i] else "");
        }
        if (!v.recursive) {
            try ev.closeScope(scope);
            return ev.finishPending(stack, v.value);
        }
        p.scope = scope;
        p.stage = .body;
        assert(v.recursive and ev.vars.contains("0"));
        try ev.push(stack, .{ .src = v.value });
    }

    /// The chosen branch or the body has a value. `foreach` repeats the body
    /// for each word and joins the results with one space.
    fn bodyDone(ev: *Evaluator, stack: *Stack, result: []const u8) Error!void {
        const p = &stack.top().pending.?;
        assert(p.stage == .body);
        const scope = p.scope orelse return ev.finishPending(stack, result);
        if (p.func != .foreach) {
            try ev.closeScope(scope);
            return ev.finishPending(stack, result);
        }
        assert(scope.index < scope.words.len);
        if (scope.index > 0) try scope.out.append(ev.arena, ' ');
        try scope.out.appendSlice(ev.arena, result);
        if (scope.out.items.len > ast.limits.expansion_bytes_max) {
            return ev.fail("expansion is longer than {d} bytes", .{ast.limits.expansion_bytes_max});
        }
        scope.index += 1;
        if (scope.index < scope.words.len) {
            if (scope.names.len > 0) try ev.setAutomatic(scope.names[0], scope.words[scope.index]);
            return ev.push(stack, .{ .src = p.raw[2] });
        }
        try ev.closeScope(scope);
        try ev.finishPending(stack, scope.out.items);
    }

    fn openScope(ev: *Evaluator, names: []const []const u8) Error!*Scope {
        const scope = try ev.arena.create(Scope);
        const saved = try ev.arena.alloc(?ast.Variable, names.len);
        for (names, saved) |name, *slot| slot.* = ev.vars.get(name);
        scope.* = .{ .names = names, .saved = saved };
        assert(scope.saved.len == names.len);
        assert(scope.index == 0);
        return scope;
    }

    fn setAutomatic(ev: *Evaluator, name: []const u8, value: []const u8) Error!void {
        assert(name.len > 0);
        try ev.vars.put(ev.arena, name, .{ .value = value, .recursive = false, .origin = .automatic });
        assert(ev.vars.get(name).?.origin == .automatic);
    }

    /// Restore the definitions that a scope shadows, last name first.
    fn closeScope(ev: *Evaluator, scope: *const Scope) Error!void {
        assert(scope.saved.len == scope.names.len);
        var i = scope.names.len;
        while (i > 0) {
            i -= 1;
            const name = scope.names[i];
            if (scope.saved[i]) |old| {
                try ev.vars.put(ev.arena, name, old);
            } else if (ev.vars.contains(name)) {
                const removed = ev.vars.remove(name);
                assert(removed);
            }
        }
        assert(i == 0);
    }

    fn emit(ev: *Evaluator, frame: *Frame, text: []const u8) Error!void {
        assert(frame.pos <= frame.src.len);
        try frame.out.appendSlice(ev.arena, text);
        if (frame.out.items.len > ast.limits.expansion_bytes_max) {
            return ev.fail("expansion is longer than {d} bytes", .{ast.limits.expansion_bytes_max});
        }
        assert(frame.out.items.len >= text.len);
    }

    /// Copy literal text up to the next `$`, then start one reference.
    fn scan(ev: *Evaluator, stack: *Stack, auto: ?*const Auto) Error!void {
        const top = stack.top();
        const rest = top.src[top.pos..];
        assert(rest.len > 0);
        const dollar = std.mem.indexOfScalar(u8, rest, '$') orelse rest.len;
        try ev.emit(top, rest[0..dollar]);
        top.pos += dollar;
        if (top.pos >= top.src.len) return;
        if (top.pos + 1 == top.src.len) {
            top.pos += 1; // A `$` at the end expands to nothing.
            return;
        }
        const c = top.src[top.pos + 1];
        if (c == '$') {
            try ev.emit(top, "$");
            top.pos += 2;
        } else if (c == '(' or c == '{') {
            const close = matchingClose(top.src, top.pos + 1) orelse {
                return ev.fail("unterminated variable reference", .{});
            };
            const inner = top.src[top.pos + 2 .. close];
            top.pos = close + 1;
            try ev.startReference(stack, inner, auto);
        } else {
            top.pos += 2;
            try ev.lookupAndPush(stack, top.src[top.pos - 1 .. top.pos], null, auto);
        }
        assert(top.pos <= top.src.len);
    }

    /// Start `$(inner)`: a function call, a substitution reference or a variable.
    fn startReference(ev: *Evaluator, stack: *Stack, inner: []const u8, auto: ?*const Auto) Error!void {
        assert(stack.len > 0);
        const pending = try ev.classifyReference(inner);
        assert(pending.n >= 1 and pending.n <= args_max);
        if (pending.func == .ref and std.mem.indexOfScalar(u8, inner, '$') == null) {
            return ev.lookupAndPush(stack, inner, null, auto);
        }
        stack.top().pending = pending;
        try ev.push(stack, .{ .src = pending.raw[0] });
    }

    fn classifyReference(ev: *Evaluator, inner: []const u8) Error!Pending {
        const word_end = std.mem.indexOfAny(u8, inner, " \t") orelse inner.len;
        const word = inner[0..word_end];
        if (word_end < inner.len and word.len > 0) {
            const args = std.mem.trimStart(u8, inner[word_end..], " \t");
            if (findSpec(word)) |spec| return ev.splitArgs(spec, args);
            for (unsupported_functions) |name| {
                if (std.mem.eql(u8, word, name)) return ev.fail("unsupported function '{s}'", .{name});
            }
        }
        if (parser.findTopLevel(inner, ":")) |colon| {
            const tail = inner[colon + 1 ..];
            if (parser.findTopLevel(tail, "=")) |eq| {
                assert(colon + 1 + eq < inner.len);
                var p: Pending = .{ .func = .subst_ref, .n = 3 };
                p.raw[0] = inner[0..colon];
                p.raw[1] = tail[0..eq];
                p.raw[2] = tail[eq + 1 ..];
                return p;
            }
        }
        var p: Pending = .{ .func = .ref, .n = 1 };
        p.raw[0] = inner;
        assert(word.len <= inner.len);
        return p;
    }

    /// Split function arguments at top-level commas. A function with a fixed
    /// maximum keeps the extra commas in its last argument.
    fn splitArgs(ev: *Evaluator, spec: Spec, args: []const u8) Error!Pending {
        var p: Pending = .{ .func = spec.func };
        const cap: u8 = if (spec.max == 0) args_max else spec.max;
        assert(cap >= spec.min and cap <= args_max);
        var rest = args;
        while (p.n < cap) {
            var comma = topLevelComma(rest);
            if (comma != null and p.n + 1 == cap) {
                if (spec.max == 0) return ev.fail("more than {d} arguments to function '{s}'", .{ args_max, spec.name });
                comma = null;
            }
            p.raw[p.n] = if (comma) |c| rest[0..c] else rest;
            p.n += 1;
            rest = rest[(comma orelse break) + 1 ..];
        }
        if (p.n < spec.min) {
            return ev.fail("insufficient number of arguments ({d}) to function '{s}'", .{ p.n, spec.name });
        }
        assert(p.n >= 1 and p.n <= args_max);
        return p;
    }

    /// All arguments of an eager call have a value. Apply the call.
    fn complete(ev: *Evaluator, stack: *Stack, p: Pending, auto: ?*const Auto) Error!void {
        assert(p.next == p.n);
        assert(stack.len >= 1);
        const r = p.results;
        switch (p.func) {
            .ref => return ev.lookupAndPush(stack, std.mem.trim(u8, r[0], ws), null, auto),
            .subst_ref => return ev.lookupAndPush(stack, std.mem.trim(u8, r[0], ws), .{ r[1], r[2] }, auto),
            else => {},
        }
        const text = try builtins.apply(ev, p.func, r[0..p.n], auto);
        try ev.emit(stack.top(), text);
    }

    /// Emit the value of variable `name`. A recursive value needs a new frame.
    fn lookupAndPush(ev: *Evaluator, stack: *Stack, name: []const u8, sub: ?[2][]const u8, auto: ?*const Auto) Error!void {
        assert(stack.len > 0);
        const top = stack.top();
        if (name.len == 0) return;
        if (try ev.autoValue(name, auto)) |value| {
            return ev.emit(top, if (sub) |s| try fns.substRef(ev.arena, s[0], s[1], value) else value);
        }
        const v = ev.lookup(name) orelse return;
        if (!v.recursive) {
            return ev.emit(top, if (sub) |s| try fns.substRef(ev.arena, s[0], s[1], v.value) else v.value);
        }
        for (stack.frames[0..stack.len]) |f| {
            const active = f.var_name orelse continue;
            if (std.mem.eql(u8, active, name)) {
                return ev.fail("Recursive variable '{s}' references itself (eventually)", .{name});
            }
        }
        try ev.push(stack, .{ .src = v.value, .var_name = name, .subst = sub });
        assert(stack.top().var_name != null);
    }

    /// Return the value of an automatic variable, or null when `name` is not one.
    pub fn autoValue(ev: *Evaluator, name: []const u8, auto: ?*const Auto) Error!?[]const u8 {
        assert(name.len > 0);
        if (name.len > 2 or std.mem.indexOfScalar(u8, "@<^+*?", name[0]) == null) return null;
        if (name.len == 2 and name[1] != 'D' and name[1] != 'F') return null;
        const a = auto orelse return "";
        const raw: []const u8 = switch (name[0]) {
            '@' => a.target,
            '<' => if (a.prerequisites.len > 0) a.prerequisites[0] else "",
            '^' => try joinWords(ev.arena, a.prerequisites, true),
            '+' => try joinWords(ev.arena, a.prerequisites, false),
            '*' => a.stem,
            '?' => try joinWords(ev.arena, a.newer, true),
            else => unreachable,
        };
        if (name.len == 1) return raw;
        assert(name.len == 2);
        return try fns.dirOrFile(ev.arena, raw, name[1]);
    }
};

/// `[A-Za-z_][A-Za-z0-9_]*`: a name that `export` with no names can export.
fn isShellName(name: []const u8) bool {
    assert(name.len > 0);
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_') return false;
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    }
    assert(name.len >= 1);
    return true;
}

/// Join words with one space. With `dedupe`, keep the first occurrence only.
fn joinWords(arena: std.mem.Allocator, words: []const []const u8, dedupe: bool) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (words, 0..) |w, i| {
        assert(w.len > 0);
        if (dedupe) {
            const seen = for (words[0..i]) |prev| {
                if (std.mem.eql(u8, prev, w)) break true;
            } else false;
            if (seen) continue;
        }
        try fns.appendWord(arena, &out, w);
    }
    assert(words.len == 0 or out.items.len > 0);
    return out.items;
}

/// Return the index of the `)` or `}` that closes the opener at `open`. Count
/// only the opener's own bracket type, as GNU Make does.
fn matchingClose(src: []const u8, open: usize) ?usize {
    assert(src[open] == '(' or src[open] == '{');
    const opener = src[open];
    const closer: u8 = if (opener == '(') ')' else '}';
    var depth: usize = 0;
    var i = open;
    while (i < src.len) : (i += 1) {
        if (src[i] == opener) depth += 1;
        if (src[i] == closer) {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    assert(depth > 0);
    return null;
}

/// Return the index of the first comma outside parentheses and braces.
fn topLevelComma(s: []const u8) ?usize {
    var depth: usize = 0;
    for (s, 0..) |c, i| {
        switch (c) {
            '(', '{' => depth += 1,
            ')', '}' => depth -|= 1,
            ',' => if (depth == 0) {
                assert(i < s.len);
                return i;
            },
            else => {},
        }
    }
    return null;
}

const testing = std.testing;

fn testEvaluator(arena: std.mem.Allocator, diag: *Diagnostic) Evaluator {
    return Evaluator.init(arena, testing.io, std.Io.Dir.cwd(), diag);
}

test "expand plain, braces, single-char and escaped references" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("A", "1", false, .file);
    try ev.define("X", "x", false, .file);
    try testing.expectEqualStrings("1-1-x-$-", try ev.expand("$(A)-${A}-$X-$$-$(NOPE)", null));
}

test "recursive values expand at use time; simple values at definition" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("B", "$(C) b", true, .file);
    try ev.define("C", "c", false, .file);
    try testing.expectEqualStrings("c b", try ev.expand("$(B)", null));
    try ev.define("C", "C2", false, .file);
    try testing.expectEqualStrings("C2 b", try ev.expand("$(B)", null));
}

test "computed names and substitution references" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("SRC", "a.c b.c", false, .file);
    try ev.define("WHICH", "SRC", false, .file);
    try ev.define("EXT", ".o", false, .file);
    try testing.expectEqualStrings("a.c b.c", try ev.expand("$($(WHICH))", null));
    try testing.expectEqualStrings("a.o b.o", try ev.expand("$(SRC:.c=.o)", null));
    try testing.expectEqualStrings("out/a.o out/b.o", try ev.expand("$(SRC:%.c=out/%$(EXT))", null));
}

test "functions" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("SRC", "a.c b.c", false, .file);
    try testing.expectEqualStrings("a.o b.o", try ev.expand("$(patsubst %.c, %.o, $(SRC))", null));
    try testing.expectEqualStrings("a-c b-c", try ev.expand("$(subst .,-,$(SRC))", null));
    try testing.expectEqualStrings("hi there", try ev.expand("$(shell echo hi; echo there)", null));
    try testing.expectEqualStrings("x(y)", try ev.expand("$(subst a,(y),xa)", null));
}

test "conditional functions expand only what they need" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try testing.expectEqualStrings("[yes] [no] []", try ev.expand("[$(if  x ,yes,no)] [$(if ,yes,no)] [$(if ,yes)]", null));
    try testing.expectEqualStrings("[b] [] [b] []", try ev.expand("[$(and a,b)] [$(and a,,b)] [$(or ,b,c)] [$(or ,)]", null));
    // The branch that is not taken never expands, so its error never fires.
    try testing.expectEqualStrings("ok", try ev.expand("$(if x,ok,$(error boom))", null));
    try testing.expectEqualStrings("ok", try ev.expand("$(or ok,$(error boom))$(and ,$(error boom))", null));
    try testing.expectEqualStrings("lt eq gt 7 ", try ev.expand("$(intcmp 1,2,lt) $(intcmp 2,2,lt,eq) $(intcmp 3,2,lt,eq,gt) $(intcmp 007,7) $(intcmp 1,7)", null));
    try testing.expectEqualStrings("eq", try ev.expand("$(intcmp 9,7,lt,eq)", null));
}

test "foreach, let and call bind and restore variables" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("x", "outer", false, .file);
    try testing.expectEqualStrings("<a> <b> <c>", try ev.expand("$(foreach x,a b c,<$(x)>)", null));
    try testing.expectEqualStrings("a  c", try ev.expand("$(foreach x,a b c,$(if $(filter b,$(x)),,$(x)))", null));
    try testing.expectEqualStrings("outer", try ev.expand("$(x)", null));
    try testing.expectEqualStrings("1|2 3", try ev.expand("$(let a b,1 2 3,$(a)|$(b))", null));
    try ev.define("O", "$(1)-$(2)-$(3)", true, .file);
    try ev.define("P", "$(call O,$(1))", true, .file);
    try ev.define("S", "$$(1)", false, .file);
    try testing.expectEqualStrings("a-b-c a-- $$(1) a --", try ev.expand("$(call O,a,b,c) $(call P,a,b,c) $(call S,x) $(call firstword,a b) $(call O,$(0))", null));
    try ev.define("reverse", "$(if $(1),$(call reverse,$(wordlist 2,$(words $(1)),$(1))) $(firstword $(1)))", true, .file);
    try testing.expectEqualStrings(" c b a", try ev.expand("$(call reverse,a b c)", null));
    try testing.expectEqual(@as(?ast.Variable, null), ev.lookup("1"));
    try testing.expectEqualStrings("automatic simple", try ev.expand("$(foreach v,a,$(origin v) $(flavor v))", null));
}

test "word and variable functions" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("R", "[$(1)]", true, .file);
    try testing.expectEqualStrings("b [] b c", try ev.expand("$(word 2,a b c) [$(word 9,a b)] $(wordlist 2,3,a b c d)", null));
    try testing.expectEqualStrings("[$(1)] recursive undefined file", try ev.expand("$(value R) $(flavor R) $(origin NOPE) $(origin R)", null));
    try testing.expectError(error.Eval, ev.expand("$(word 0,a b)", null));
    try testing.expectEqualStrings("*** first argument to 'word' function must be greater than 0.  Stop.", diag.message());
    try testing.expectError(error.Eval, ev.expand("$(word x,a b)", null));
    try testing.expectEqualStrings("*** non-numeric first argument to 'word' function: 'x'.  Stop.", diag.message());
    try testing.expectError(error.Eval, ev.expand("$(wordlist 0,2,a)", null));
    try testing.expectEqualStrings("*** invalid first argument to 'wordlist' function: '0'.  Stop.", diag.message());
    try testing.expectError(error.Eval, ev.expand("$(foreach a,b)", null));
    try testing.expectEqualStrings("*** insufficient number of arguments (2) to function 'foreach'.  Stop.", diag.message());
    try testing.expectError(error.Eval, ev.expand("$(error boom here)", null));
    try testing.expectEqualStrings("*** boom here.  Stop.", diag.message());
    try testing.expectEqualStrings("a,b", try ev.expand("$(strip a,b)", null));
}

test "automatic variables" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    const auto: Auto = .{
        .target = "out/app",
        .prerequisites = &.{ "src/a.o", "b.o", "src/a.o" },
        .stem = "app",
        .newer = &.{"b.o"},
    };
    const got = try ev.expand("$@ $< [$^] [$+] $* $? $(@D) $(@F) ${<D}", &auto);
    try testing.expectEqualStrings("out/app src/a.o [src/a.o b.o] [src/a.o b.o src/a.o] app b.o out app src", got);
    try testing.expectEqualStrings(" ", try ev.expand("$@ $<", null));
}

test "evaluation errors" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("LOOP", "x $(LOOP2)", true, .file);
    try ev.define("LOOP2", "$(LOOP)", true, .file);
    try testing.expectError(error.Eval, ev.expand("$(LOOP)", null));
    try testing.expectEqualStrings("*** Recursive variable 'LOOP' references itself (eventually).  Stop.", diag.message());
    try testing.expectError(error.Eval, ev.expand("$(guile (+ 1 2))", null));
    try testing.expectEqualStrings("*** unsupported function 'guile'.  Stop.", diag.message());
    try testing.expectError(error.Eval, ev.expand("$(subst a,b)", null));
    try testing.expectError(error.Eval, ev.expand("$(A", null));
}

test "export decisions follow GNU Make" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    const v = struct {
        fn of(origin: ast.Origin) ast.Variable {
            return .{ .value = "x", .recursive = false, .origin = origin };
        }
    }.of;
    try testing.expect(ev.exported("CLI", v(.command_line), false));
    try testing.expect(ev.exported("PATH", v(.file), true));
    try testing.expect(!ev.exported("LOCAL", v(.file), false));
    try testing.expect(!ev.exported("SHELL", v(.file), true));
    try testing.expect(!ev.exported("MAKE", v(.default), false));
    ev.export_all = true;
    try testing.expect(ev.exported("LOCAL", v(.file), false));
    try testing.expect(!ev.exported("B.C", v(.file), false));
    try testing.expect(!ev.exported("CC", v(.default), false));
    try ev.setExport("LOCAL", false);
    try testing.expect(!ev.exported("LOCAL", v(.file), false));
    try ev.setExport("B.C", true);
    try testing.expect(ev.exported("B.C", v(.file), false));
}

test "deep nesting fails at the depth limit" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    var text: std.ArrayList(u8) = .empty;
    for (0..ast.limits.expansion_depth_max + 1) |_| try text.appendSlice(arena.allocator(), "$(subst a,b,");
    try text.appendSlice(arena.allocator(), "a");
    for (0..ast.limits.expansion_depth_max + 1) |_| try text.append(arena.allocator(), ')');
    try testing.expectError(error.Eval, ev.expand(text.items, null));
}

test "origin precedence" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("CC", "clang", false, .command_line);
    try ev.define("CC", "gcc", false, .file);
    try testing.expectEqualStrings("clang", ev.lookup("CC").?.value);
    try ev.define("HOME", "/env", true, .environment);
    try ev.define("HOME", "/file", true, .file);
    try testing.expectEqualStrings("/file", ev.lookup("HOME").?.value);
}
