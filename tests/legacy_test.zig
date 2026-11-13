//! Legacy mode tests: POSIX and GNU Make syntax with tab recipes and `.PHONY`.

const std = @import("std");
const zmake = @import("zmake");
const ast = zmake.ast;
const testing = std.testing;

fn parseLegacy(arena: std.mem.Allocator, src: []const u8) !ast.Makefile {
    var diag: zmake.Diagnostic = .{};
    return zmake.parser.parse(arena, src, "Makefile", .legacy, &diag);
}

const c_project =
    "# A small C project.\n" ++
    "CC := gcc\n" ++
    "CFLAGS = -O2 \\\n" ++
    "         -Wall\n" ++
    "OBJS = main.o util.o\n" ++
    "\n" ++
    ".PHONY: all clean\n" ++
    "\n" ++
    "all: app\n" ++
    "\n" ++
    "app: $(OBJS)\n" ++
    "\t$(CC) -o $@ $^\n" ++
    "\n" ++
    "%.o: %.c\n" ++
    "\t$(CC) $(CFLAGS) -c $< -o $@\n" ++
    "\n" ++
    "clean:\n" ++
    "\t-rm -f app *.o\n" ++
    "\n";

test "legacy C project statements" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mk = try parseLegacy(arena.allocator(), c_project);
    try testing.expectEqual(ast.SyntaxMode.legacy, mk.mode);
    try testing.expectEqual(@as(usize, 8), mk.statements.len);
    const cc = mk.statements[0].assignment;
    try testing.expectEqualStrings("CC", cc.name);
    try testing.expectEqual(ast.VariableFlavor.simple, cc.flavor);
    try testing.expectEqualStrings("-O2 -Wall", mk.statements[1].assignment.value);
    const phony = mk.statements[3].rule;
    try testing.expectEqualStrings(".PHONY", phony.targets);
    try testing.expectEqualStrings("all clean", phony.prerequisites);
    try testing.expect(!phony.has_recipe);
    const app = mk.statements[5].rule;
    try testing.expectEqualStrings("$(OBJS)", app.prerequisites);
    try testing.expectEqualStrings("$(CC) -o $@ $^", app.recipes[0].text);
    try testing.expectEqual(@as(u32, 11), app.line);
    const pattern = mk.statements[6].rule;
    try testing.expectEqualStrings("%.o", pattern.targets);
    try testing.expectEqualStrings("%.c", pattern.prerequisites);
    const clean = mk.statements[7].rule;
    try testing.expect(clean.recipes[0].ignore_error);
    try testing.expect(!clean.task);
}

test "legacy mode rejects space-indented recipes" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: zmake.Diagnostic = .{};
    const src = "all:\n    echo hi\n";
    try testing.expectError(error.Syntax, zmake.parser.parse(arena.allocator(), src, "Makefile", .legacy, &diag));
    try testing.expectEqualStrings("Makefile:2: *** missing separator.  Stop.", diag.message());
}

test "legacy mode reads @name and task as plain target names" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mk = try parseLegacy(arena.allocator(), "@deploy: build\ntask clean:\n");
    try testing.expectEqualStrings("@deploy", mk.statements[0].rule.targets);
    try testing.expect(!mk.statements[0].rule.task);
    try testing.expectEqualStrings("task clean", mk.statements[1].rule.targets);
    try testing.expect(!mk.statements[1].rule.task);
}

test "legacy comments and blank lines inside a recipe" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mk = try parseLegacy(arena.allocator(), "a:\n\techo 1\n\n# note\n\techo 2\nb:\n");
    try testing.expectEqual(@as(usize, 2), mk.statements.len);
    try testing.expectEqual(@as(usize, 2), mk.statements[0].rule.recipes.len);
    try testing.expectEqualStrings("echo 2", mk.statements[0].rule.recipes[1].text);
}

test "default goal assignment" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mk = try parseLegacy(arena.allocator(), ".DEFAULT_GOAL := test\n");
    try testing.expectEqualStrings(".DEFAULT_GOAL", mk.statements[0].assignment.name);
    try testing.expectEqualStrings("test", mk.statements[0].assignment.value);
}
