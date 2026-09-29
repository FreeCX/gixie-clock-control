const std = @import("std");
const json = std.json;

const max_file_size = 1024 * 1024;

pub fn parseConfigAlloc(
    comptime T: type,
    io: std.Io,
    gpa: std.mem.Allocator,
    filename: []const u8,
) !json.Parsed(T) {
    const buffer = try std.Io.Dir.cwd().readFileAlloc(
        io,
        filename,
        gpa,
        .limited(max_file_size),
    );
    defer gpa.free(buffer);

    return try json.parseFromSlice(
        T,
        gpa,
        buffer,
        .{ .ignore_unknown_fields = true },
    );
}
