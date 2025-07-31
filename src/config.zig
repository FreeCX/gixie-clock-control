const std = @import("std");
const json = std.json;

pub const Config = struct {
    clock: struct {
        host: []u8,
        port: u16,
    },
    position: struct {
        latitude: f64,
        longitude: f64,
        elevation: f64,
    }
};

const max_file_size = 1024 * 1024;

pub fn parseConfigAlloc(filename: []const u8, allocator: std.mem.Allocator) !json.Parsed(Config) {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const buffer = try file.readToEndAlloc(allocator, max_file_size);
    defer allocator.free(buffer);

    return try json.parseFromSlice(Config, allocator, buffer, .{});
}
