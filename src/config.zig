const std = @import("std");
const json = std.json;

const max_file_size = 1024 * 1024;

pub fn parseConfigAlloc(comptime T: type, filename: []const u8, allocator: std.mem.Allocator) !json.Parsed(T) {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const buffer = try file.readToEndAlloc(allocator, max_file_size);
    defer allocator.free(buffer);

    return try json.parseFromSlice(T, allocator, buffer, .{ .ignore_unknown_fields = true });
}
