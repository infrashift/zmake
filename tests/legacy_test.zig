//! Legacy mode tests. Phase 2 adds the parser cases.

const std = @import("std");
const zmake = @import("zmake");

test "legacy mode name" {
    try std.testing.expectEqualStrings("legacy", @tagName(zmake.ast.SyntaxMode.legacy));
}
