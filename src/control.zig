const std = @import("std");
const log = std.log;
const mem = std.mem;
const process = std.process;
const suninfo = @import("suninfo.zig");
const api = @import("api.zig");
const cfg = @import("config.zig");
const stdout = @import("stdout.zig");

pub const Config = struct {
    // zig fmt: off
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
    control: struct {
        min: i32,
        max: i32,
        step: i32,
    },
    // zig fmt: on

    fn createTransitionIterator(self: Config, current: i32) TransitionIterator {
        if (current > self.control.min) {
            return TransitionIterator{ .start = self.control.max, .stop = self.control.min, .step = -self.control.step };
        } else {
            return TransitionIterator{ .start = self.control.min, .stop = self.control.max, .step = self.control.step };
        }
    }
};

const TransitionIterator = struct {
    start: i32,
    stop: i32,
    step: i32,

    fn next(self: *TransitionIterator) ?i32 {
        const current = self.start;
        const is_increment = self.step > 0;
        const is_bigger = is_increment and self.start > self.stop;
        const is_lower = !is_increment and self.start < self.stop;
        if (is_lower or is_bigger) {
            return null;
        }
        self.start += self.step;
        return current;
    }
};

fn updateCrontab(app: []u8, config: Config, out: *std.io.Writer, allocator: std.mem.Allocator) !void {
    const max_file_size = 1024;

    const file = try std.fs.cwd().openFile("/etc/crontabs/root", .{});
    defer file.close();
    const current_crontab = try file.readToEndAlloc(allocator, max_file_size);
    defer allocator.free(current_crontab);

    const info = try suninfo.calculate(config.position.latitude, config.position.longitude, config.position.elevation, config.position.timezone);

    try out.print("{s}\n", .{current_crontab});
    try out.print("# gixie control app\n", .{});
    try out.print("@daily {s} crontab | crontab -\n", .{app});
    try out.print("{d} {d} * * * {s}\n", .{ info.sunrise.minute, info.sunrise.hour, app });
    try out.print("{d} {d} * * * {s}\n", .{ info.sunset.minute, info.sunset.hour, app });
    try out.flush();
}

fn changeBrightness(config: Config, out: *std.io.Writer, allocator: std.mem.Allocator) !void {
    const address = try std.net.Address.parseIp4(config.clock.host, config.clock.port);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();

    // we don't support frame payload > 127
    var buffer: [127]u8 = undefined;
    var reader_stream = stream.reader(&buffer);
    var writer_stream = stream.writer(&buffer);

    var gixie = try api.Api.init(config.clock.host, config.clock.port, reader_stream.interface(), &writer_stream.interface);

    const current = try gixie.get(.Brightness, allocator);
    var iter = config.createTransitionIterator(current);

    try out.print("brightness: {d} -> {d}\n", .{ current, iter.stop });
    try out.flush();

    while (iter.next()) |value| {
        try gixie.set(.Brightness, value, allocator);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // application args
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    // full path to app
    const app = try std.fs.cwd().realpathAlloc(allocator, args[0]);
    defer allocator.free(app);

    // full path to config
    const parent_path = std.fs.path.dirname(app).?;
    const config_file = try std.fs.path.join(allocator, &[_][]const u8{ parent_path, "config.json" });
    defer allocator.free(config_file);

    // setup stdout and stderr with fixed buffer size
    const out = stdout.setup(1024);

    const parsed = cfg.parseConfigAlloc(Config, config_file, allocator) catch |err| {
        try out.stderr.print("Cannot load config: {any}\n", .{err});
        try out.stderr.flush();
        return;
    };
    defer parsed.deinit();
    const config = parsed.value;

    if (args.len == 2 and mem.eql(u8, args[1], "crontab")) {
        updateCrontab(app, config, out.stdout, allocator) catch |err| {
            try out.stderr.print("Cannot update crontab: {any}\n", .{err});
            try out.stderr.flush();
        };
    } else {
        changeBrightness(config, out.stdout, allocator) catch |err| {
            try out.stderr.print("Cannot change brightness: {any}\n", .{err});
            try out.stderr.flush();
        };
    }
}
