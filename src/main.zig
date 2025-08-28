const std = @import("std");
const log = std.log;
const mem = std.mem;
const process = std.process;
const suninfo = @import("suninfo.zig");
const api = @import("api.zig");
const cfg = @import("config.zig");
const stdout = @import("stdout.zig");

// zig fmt: off
pub const Config = struct {
    clock: struct {
        host: []u8,
        port: u16,
    },
    position: struct {
        latitude: f64,
        longitude: f64,
        elevation: f64,
        timezone: i8,
    }
};
// zig fmt: on

fn printUsage(out: *std.io.Writer) !void {
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
    try out.print(usage, .{});
    try out.flush();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // setup stdout and stderr with fixed buffer size
    const out = stdout.setup(1024);

    const parsed = cfg.parseConfigAlloc(Config, "config.json", allocator) catch |err| {
        try out.stderr.print("Problem with config loading: {any}\n", .{err});
        return;
    };
    defer parsed.deinit();
    const config = parsed.value;

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len == 1 or args.len > 3) {
        try printUsage(out.stdout);
        return;
    }

    const isSuninfo = mem.eql(u8, args[1], "suninfo");
    const isGet = mem.eql(u8, args[1], "get");
    const isSet = mem.eql(u8, args[1], "set");

    if (!isSuninfo and !isGet and !isSet) {
        try printUsage(out.stdout);
        return;
    }

    if (isSuninfo) {
        const result = try suninfo.calculate(config.position.latitude, config.position.longitude, config.position.elevation, config.position.timezone);
        try out.stdout.print("sunrise: {f}\n", .{result.sunrise});
        try out.stdout.print(" sunset: {f}\n", .{result.sunset});
        try out.stdout.flush();
        return;
    }

    const address = try std.net.Address.parseIp4(config.clock.host, config.clock.port);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();

    // we don't support frame payload > 127
    var buffer: [127]u8 = undefined;
    var reader_stream = stream.reader(&buffer);
    var writer_stream = stream.writer(&buffer);

    var gixie = try api.Api.init(config.clock.host, config.clock.port, reader_stream.interface(), &writer_stream.interface);

    if (isGet) {
        const current_brightness = try gixie.get(.Brightness, allocator);
        try out.stdout.print("brightness: {d}\n", .{current_brightness});
        try out.stdout.flush();
        return;
    }

    if (isSet) {
        const new_value = try std.fmt.parseInt(i32, args[2], 10);
        try gixie.set(.Brightness, new_value, allocator);
        try out.stdout.print("brightness -> {d}\n", .{new_value});
        try out.stdout.flush();
    }
}
