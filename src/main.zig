const std = @import("std");
const net = std.net;
const log = std.log;
const mem = std.mem;
const io = std.io;
const process = std.process;
const suninfo = @import("suninfo.zig");
const api = @import("api.zig");

fn printUsage(stdout: io.AnyWriter) !void {
    const usage =
        \\usage: [command] [args]
        \\
        \\Gixie Clock Control
        \\
        \\Commands:
        \\  get        Get current brightness
        \\  set        Set new brightness
        \\  suninfo    Get todays sunrise and sunset info
        \\
    ;
    try stdout.print(usage, .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    const stdout = io.getStdOut().writer();

    const config = .{
        .address = "192.168.88.97",
        .port = 81,
        .latitude = 48.7194,
        .longitude = 44.5018,
    };

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len == 1 or args.len > 3) {
        try printUsage(stdout.any());
        return;
    }

    const isSuninfo = mem.eql(u8, args[1], "suninfo");
    const isGet = mem.eql(u8, args[1], "get");
    const isSet = mem.eql(u8, args[1], "set");

    if (!isSuninfo and !isGet and !isSet) {
        try printUsage(stdout.any());
        return;
    }

    if (isSuninfo) {
        const result = try suninfo.calculate(config.latitude, config.longitude, 0);
        try stdout.print("sunrise: {d:02}:{d:02}\n", .{ result.sunrise.hour, result.sunrise.minute });
        try stdout.print(" sunset: {d:02}:{d:02}\n", .{ result.sunset.hour, result.sunset.minute });
        return;
    }

    const address = try net.Address.parseIp4(config.address, config.port);
    var gixie = try api.Api.init(address, allocator);
    defer gixie.deinit();

    if (isGet) {
        const current_brightness = try gixie.get(.Brightness);
        try stdout.print("brightness: {d}\n", .{current_brightness});
        return;
    }

    if (isSet) {
        const new_value = try std.fmt.parseInt(i32, args[2], 10);
        try gixie.set(.Brightness, new_value);
        try stdout.print("brightness -> {d}\n", .{new_value});
    }
}
