const std = @import("std");
const log = std.log;
const mem = std.mem;
const io = std.io;
const process = std.process;
const suninfo = @import("suninfo.zig");
const api = @import("api.zig");
const cfg = @import("config.zig");

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
    },
    control: struct {
        min: i32,
        max: i32,
        step: i32,
    }
};
// zig fmt: on

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

fn updateCrontab(app: []u8, config: Config, allocator: std.mem.Allocator) !void {
    const max_file_size = 1024;

    const file = try std.fs.cwd().openFile("/etc/crontabs/root", .{});
    defer file.close();
    const current_crontab = try file.readToEndAlloc(allocator, max_file_size);
    defer allocator.free(current_crontab);

    const info = try suninfo.calculate(config.position.latitude, config.position.longitude, config.position.elevation, config.position.timezone);

    const stdout = io.getStdOut().writer();
    try stdout.print("{s}\n", .{current_crontab});
    try stdout.print("# {s}\n", .{app});
    try stdout.print("@daily {s} crontab | crontab -\n", .{app});
    try stdout.print("{d} {d} * * * {s}\n", .{ info.sunrise.minute, info.sunrise.hour, app });
    try stdout.print("{d} {d} * * * {s}\n", .{ info.sunset.minute, info.sunset.hour, app });
}

fn changeBrightness(config: Config, allocator: std.mem.Allocator) !void {
    var gixie = try api.Api.init(config.clock.host, config.clock.port, allocator);
    defer gixie.deinit();

    const from_value = try gixie.get(.Brightness);
    const to_value = if (from_value > config.control.min) config.control.min else config.control.max;
    const sign: i32 = if (from_value > to_value) -1 else 1;

    const stdout = io.getStdOut().writer();
    try stdout.print("brightness: {d} -> {d}\n", .{ from_value, to_value });

    var iter = TransitionIterator{ .start = from_value, .stop = to_value, .step = config.control.step * sign };
    while (iter.next()) |value| {
        try gixie.set(.Brightness, value);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const stderr = io.getStdErr().writer();

    const parsed = cfg.parseConfigAlloc(Config, "config.json", allocator) catch |err| {
        try stderr.print("Cannot load config: {any}\n", .{err});
        return;
    };
    defer parsed.deinit();
    const config = parsed.value;

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    const app = try std.fs.cwd().realpathAlloc(allocator, args[0]);
    defer allocator.free(app);

    if (args.len == 2 and mem.eql(u8, args[1], "crontab")) {
        updateCrontab(app, config, allocator) catch |err| {
            try stderr.print("Cannot update crontab: {any}\n", .{err});
        };
    } else {
        changeBrightness(config, allocator) catch |err| {
            try stderr.print("Cannot change brightness: {any}\n", .{err});
        };
    }
}
