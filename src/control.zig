const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const process = std.process;

const suninfo = @import("suninfo.zig");
const api = @import("api.zig");
const cfg = @import("config.zig");

const log = std.log.scoped(.app);

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
    },

    fn createTransitionIterator(self: Config, current: i32) TransitionIterator {
        return TransitionIterator{
            .start = self.control.max,
            .stop = self.control.min,
            .step = if (current > self.control.min) -self.control.step else self.control.step,
        };
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

fn updateCrontab(io: Io, gpa: mem.Allocator, app: []u8, config: Config, out: *Io.Writer) !void {
    const max_file_size = 1024;

    const current_crontab = try std.Io.Dir.cwd().readFileAlloc(
        io,
        "/etc/crontabs/root",
        gpa,
        .limited(max_file_size),
    );
    defer gpa.free(current_crontab);

    const info = try suninfo.calculate(
        io,
        config.position.latitude,
        config.position.longitude,
        config.position.elevation,
        config.position.timezone,
    );

    try out.print("{s}\n", .{current_crontab});
    try out.print("# gixie control app\n", .{});
    try out.print("@daily {s} crontab | crontab -\n", .{app});
    try out.print("{d} {d} * * * {s}\n", .{ info.sunrise.minute, info.sunrise.hour, app });
    try out.print("{d} {d} * * * {s}\n", .{ info.sunset.minute, info.sunset.hour, app });
    try out.flush();
}

fn changeBrightness(io: Io, gpa: mem.Allocator, config: Config, out: *Io.Writer) !void {
    const address = try std.Io.net.IpAddress.parseIp4(config.clock.host, config.clock.port);
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

    const current = try gixie.get(.Brightness, gpa);
    var iter = config.createTransitionIterator(current);

    try out.print("brightness: {d} -> {d}\n", .{ current, iter.stop });
    try out.flush();

    while (iter.next()) |value| {
        try gixie.set(.Brightness, value, gpa);
    }
}

pub fn main(init: process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // application args
    const args = try init.minimal.args.toSlice(gpa);
    defer gpa.free(args);

    // full path to app
    const app = try std.Io.Dir.cwd().realPathFileAlloc(io, args[0], gpa);
    defer gpa.free(app);

    // full path to config
    const parent_path = std.fs.path.dirname(app).?;
    const config_file = try std.fs.path.join(gpa, &[_][]const u8{ parent_path, "config.json" });
    defer gpa.free(config_file);

    // setup stdout and stderr with fixed buffer size
    var stdout_buffer: [1024]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;

    const parsed = cfg.parseConfigAlloc(
        Config,
        io,
        gpa,
        config_file,
    ) catch |err| {
        try stderr.print("Cannot load config: {any}\n", .{err});
        try stderr.flush();
        return;
    };
    defer parsed.deinit();
    const config = parsed.value;

    if (args.len == 2 and mem.eql(u8, args[1], "crontab")) {
        updateCrontab(io, gpa, app, config, stdout) catch |err| {
            try stderr.print("Cannot update crontab: {any}\n", .{err});
            try stderr.flush();
        };
    } else {
        changeBrightness(io, gpa, config, stdout) catch |err| {
            try stderr.print("Cannot change brightness: {any}\n", .{err});
            try stderr.flush();
        };
    }
}
