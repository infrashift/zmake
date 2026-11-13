//! Modern mode tests: `@task`, `task name:`, space indentation and `.PHONY`.

const std = @import("std");
const zmake = @import("zmake");
const ast = zmake.ast;
const testing = std.testing;

fn parseModern(arena: std.mem.Allocator, src: []const u8) !ast.Makefile {
    var diag: zmake.Diagnostic = .{};
    return zmake.parser.parse(arena, src, "ZMakefile", .modern, &diag);
}

test "@task with 4-space indentation" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const src = "build:\n    echo build\n\n@deploy: build\n    echo deploy\n    @echo done\n";
    const mk = try parseModern(arena.allocator(), src);
    try testing.expectEqual(ast.SyntaxMode.modern, mk.mode);
    try testing.expectEqual(@as(usize, 2), mk.statements.len);
    const build = mk.statements[0].rule;
    try testing.expectEqualStrings("build", build.targets);
    try testing.expect(!build.task);
    const deploy = mk.statements[1].rule;
    try testing.expectEqualStrings("deploy", deploy.targets);
    try testing.expectEqualStrings("build", deploy.prerequisites);
    try testing.expect(deploy.task);
    try testing.expectEqual(@as(usize, 2), deploy.recipes.len);
    try testing.expect(deploy.recipes[1].silent);
    try testing.expectEqualStrings("echo done", deploy.recipes[1].text);
}

test "task keyword and 2-space indentation" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mk = try parseModern(arena.allocator(), "task test: build\n  zig build test\n");
    const r = mk.statements[0].rule;
    try testing.expectEqualStrings("test", r.targets);
    try testing.expect(r.task);
    try testing.expectEqualStrings("zig build test", r.recipes[0].text);
}

test "tabs still work and mix with spaces between blocks" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mk = try parseModern(arena.allocator(), "a:\n\techo a\nb:\n    echo b\n");
    try testing.expectEqualStrings("echo a", mk.statements[0].rule.recipes[0].text);
    try testing.expectEqualStrings("echo b", mk.statements[1].rule.recipes[0].text);
}

test "blank lines and comments do not end a modern recipe block" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mk = try parseModern(arena.allocator(), "a:\n  echo 1\n\n# column-0 comment\n\n  echo 2\nX = 1\n");
    try testing.expectEqual(@as(usize, 2), mk.statements.len);
    try testing.expectEqual(@as(usize, 2), mk.statements[0].rule.recipes.len);
    try testing.expectEqualStrings("X", mk.statements[1].assignment.name);
}

test ".PHONY still parses in modern mode" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mk = try parseModern(arena.allocator(), ".PHONY: clean\nclean:\n    rm -rf out\n");
    try testing.expectEqualStrings(".PHONY", mk.statements[0].rule.targets);
    try testing.expectEqualStrings("clean", mk.statements[0].rule.prerequisites);
}

test "modern task syntax errors" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: zmake.Diagnostic = .{};
    const a = arena.allocator();
    try testing.expectError(error.Syntax, zmake.parser.parse(a, "@a b:\n", "ZMakefile", .modern, &diag));
    try testing.expectEqualStrings("ZMakefile:1: *** mix of tasks and other targets in one rule.  Stop.", diag.message());
    try testing.expectError(error.Syntax, zmake.parser.parse(a, "@:\n", "ZMakefile", .modern, &diag));
    // `task:` with no name is a plain target named `task`.
    const plain = try zmake.parser.parse(a, "task :\n", "ZMakefile", .modern, &diag);
    try testing.expectEqualStrings("task", plain.statements[0].rule.targets);
    try testing.expect(!plain.statements[0].rule.task);
    try testing.expectError(error.Syntax, zmake.parser.parse(a, "task @x:\n", "ZMakefile", .modern, &diag));
}

test "multiple tasks in one rule" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mk = try parseModern(arena.allocator(), "@fmt @lint:\n    echo check\n");
    try testing.expectEqualStrings("fmt lint", mk.statements[0].rule.targets);
    try testing.expect(mk.statements[0].rule.task);
}
