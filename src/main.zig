const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const process = std.process;

const suninfo = @import("suninfo.zig");
const api = @import("api.zig");
const cfg = @import("config.zig");

const log = std.log.scoped(.app);

// TODO:
//  - использовать https://github.com/Hejsil/zig-clap
//  - внедрить функционал `control.zig` сюда
//  - реализовать работу с cron и systemd
//  - добавить установку яркости используя TransitionIterator
//  - обновить систему сборки

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
    },
};

fn printUsage(out: *Io.Writer) !void {
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

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // setup stdout and stderr with fixed buffer size
    var stdout_buffer: [1024]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    var stderr_writer = Io.File.stderr().writer(io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;

    const parsed = cfg.parseConfigAlloc(
        Config,
        io,
        gpa,
        "config.json",
    ) catch |err| {
        try stderr.print("Problem with config loading: {any}\n", .{err});
        return;
    };
    defer parsed.deinit();
    const config = parsed.value;

    const args = try init.minimal.args.toSlice(gpa);
    defer gpa.free(args);

    if (args.len == 1 or args.len > 3) {
        try printUsage(stdout);
        return;
    }

    var command: enum { suninfo, get, set, not_set } = .not_set;
    if (mem.eql(u8, args[1], "suninfo")) command = .suninfo;
    if (mem.eql(u8, args[1], "get")) command = .get;
    if (mem.eql(u8, args[1], "set")) command = .set;

    if (command == .not_set) {
        try printUsage(stdout);
        return;
    }

    if (command == .suninfo) {
        const result = try suninfo.calculate(
            io,
            config.position.latitude,
            config.position.longitude,
            config.position.elevation,
            config.position.timezone,
        );
        try stdout.print("sunrise: {f}\n", .{result.sunrise});
        try stdout.print(" sunset: {f}\n", .{result.sunset});
        try stdout.flush();
        return;
    }

    const address = try Io.net.IpAddress.parseIp4(config.clock.host, config.clock.port);
    const stream = try address.connect(io, .{ .mode = .stream });
    defer stream.close(io);

    // we don't support frame payload > 127
    var read_buffer: [127]u8 = undefined;
    var write_buffer: [127]u8 = undefined;
    var reader_stream = stream.reader(io, &read_buffer);
    var writer_stream = stream.writer(io, &write_buffer);

    var gixie = try api.Api.init(
        config.clock.host,
        config.clock.port,
        &reader_stream.interface,
        &writer_stream.interface,
    );

    switch (command) {
        .get => {
            const current_brightness = try gixie.get(gpa, .Brightness);
            try stdout.print("brightness: {d}\n", .{current_brightness});
            try stdout.flush();
        },
        .set => {
            const new_value = try std.fmt.parseInt(i32, args[2], 10);
            try gixie.set(gpa, .Brightness, new_value);
            try stdout.print("brightness -> {d}\n", .{new_value});
            try stdout.flush();
        },
        else => {},
    }
}
