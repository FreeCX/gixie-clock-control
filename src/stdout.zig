const std = @import("std");

// simple stdout/stderr wrapper
pub fn setup(buffer_suze: usize) type {
    return struct {
        var buffer: [buffer_suze]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&buffer);
        var stderr_writer = std.fs.File.stderr().writer(&buffer);
        pub const stdout = &stdout_writer.interface;
        pub const stderr = &stderr_writer.interface;
    };
}
