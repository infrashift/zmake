//! A fixed-size diagnostic message. Zig errors carry no payload, so each module
//! writes the human-readable text here before it returns an error.

const std = @import("std");
const assert = std.debug.assert;

pub const Diagnostic = struct {
    buf: [capacity]u8 = undefined,
    len: usize = 0,

    pub const capacity = 1024;

    /// Format the message. A message longer than the buffer ends with "...".
    pub fn set(d: *Diagnostic, comptime fmt: []const u8, args: anytype) void {
        assert(d.len <= capacity);
        if (std.fmt.bufPrint(&d.buf, fmt, args)) |out| {
            d.len = out.len;
        } else |err| switch (err) {
            error.NoSpaceLeft => {
                @memcpy(d.buf[capacity - 3 ..], "...");
                d.len = capacity;
            },
        }
        assert(d.len <= capacity);
    }

    pub fn message(d: *const Diagnostic) []const u8 {
        assert(d.len <= capacity);
        return d.buf[0..d.len];
    }
};

test "diagnostic formats a message" {
    var d: Diagnostic = .{};
    d.set("{s}:{d}: bad", .{ "Makefile", 3 });
    try std.testing.expectEqualStrings("Makefile:3: bad", d.message());
}

test "diagnostic truncates a long message" {
    var d: Diagnostic = .{};
    const long: [Diagnostic.capacity + 10]u8 = @splat('x');
    d.set("{s}", .{&long});
    try std.testing.expectEqual(@as(usize, Diagnostic.capacity), d.message().len);
    try std.testing.expect(std.mem.endsWith(u8, d.message(), "..."));
}
