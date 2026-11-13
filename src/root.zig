//! zmake library root. The executable and the tests import the modules from here.

pub const ast = @import("ast.zig");
pub const cli = @import("cli.zig");
pub const diag = @import("diag.zig");
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const functions = @import("functions.zig");
pub const eval = @import("eval.zig");
pub const database = @import("database.zig");
pub const dag = @import("dag.zig");
pub const Diagnostic = diag.Diagnostic;

test {
    @import("std").testing.refAllDecls(@This());
}
