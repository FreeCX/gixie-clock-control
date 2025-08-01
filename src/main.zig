const std = @import("std");
const log = std.log;
const mem = std.mem;
const io = std.io;
const process = std.process;
const suninfo = @import("suninfo.zig");
const api = @import("api.zig");
const cfg = @import("config.zig");

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
    const stderr = io.getStdErr().writer();

    const parsed = cfg.parseConfigAlloc("config.json", allocator) catch |err| {
        try stderr.print("Problem with config loading: {}\n", .{err});
        return;
    };
    defer parsed.deinit();
    const config = parsed.value;

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
        const result = try suninfo.calculate(config.position.latitude, config.position.longitude, config.position.elevation, config.position.timezone);
        try stdout.print("sunrise: {d:02}:{d:02}\n", .{ result.sunrise.hour, result.sunrise.minute });
        try stdout.print(" sunset: {d:02}:{d:02}\n", .{ result.sunset.hour, result.sunset.minute });
        return;
    }

    var gixie = try api.Api.init(config.clock.host, config.clock.port, allocator);
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
