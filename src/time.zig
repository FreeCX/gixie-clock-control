const std = @import("std");
const log = std.log;

const unix_const = 2440587.5; // 01-01-1970, 00:00:00
const secs_per_min = 60;
const secs_per_hour = secs_per_min * 60;
const secs_per_day = secs_per_hour * 24;

pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,

    pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{:0>2}:{:0>2}:{:0>2}", .{ self.hour, self.minute, self.second });
    }
};

pub fn nowJulianDate() f64 {
    const now: f64 = @floatFromInt(std.time.timestamp());
    log.debug("Now = {d:.0}", .{now});
    return now / secs_per_day + unix_const;
}

pub fn reverseJulian(timestamp: f64) f64 {
    return (timestamp - unix_const) * secs_per_day;
}

pub fn fromTimestamp(timestamp: f64, timezone: i8) Time {
    const dt: u64 = @intFromFloat(timestamp);
    const hour: i8 = @intCast(@divTrunc(@rem(dt, secs_per_day), secs_per_hour));
    const minute: u8 = @intCast(@divTrunc(@rem(dt, secs_per_hour), secs_per_min));
    const second: u8 = @intCast(@rem(dt, secs_per_min));

    return Time{
        .hour = @intCast(@rem(hour + timezone, 24)),
        .minute = minute,
        .second = second,
    };
}
