const std = @import("std");
const net = std.net;
const log = std.log;
const suninfo = @import("suninfo.zig");
const api = @import("api.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer if (gpa.deinit() == .leak) {
        std.log.err("Memory leak", .{});
    };
    const stdout = std.io.getStdOut().writer();

    const config = .{
        .address = "192.168.88.97",
        .port = 81,
        .latitude = 48.7194,
        .longitude = 44.5018,
    };

    const address = try net.Address.parseIp4(config.address, config.port);
    var gixie = try api.Api.init(address, allocator);
    defer gixie.deinit();

    const value = try gixie.get(.Brightness);
    try stdout.print("brightness: {d}\n", .{value});

    const result = try suninfo.calculate(config.latitude, config.longitude, 0);
    try stdout.print("sunrise: {d:02}:{d:02}\n", .{ result.sunrise.hour, result.sunrise.minute });
    try stdout.print(" sunset: {d:02}:{d:02}\n", .{ result.sunset.hour, result.sunset.minute });
}
