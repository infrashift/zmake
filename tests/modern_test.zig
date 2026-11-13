//! Modern mode tests. Phase 2 adds the parser cases.

const std = @import("std");
const zmake = @import("zmake");

test "modern mode name" {
    try std.testing.expectEqualStrings("modern", @tagName(zmake.ast.SyntaxMode.modern));
}
