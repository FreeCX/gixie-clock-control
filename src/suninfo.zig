const std = @import("std");
const log = std.log;
const math = std.math;
const time = std.time;
const cTime = @cImport({
    @cInclude("time.h");
});

const Time = struct { hour: u8, minute: u8 };
const SunInfo = struct { sunrise: Time, sunset: Time };

const noon_const = 2451545.0; // 01-01-2000, 12:00:00
const unix_const = 2440587.5; // 01-01-1970, 00:00:00
const seconds_in_day = 60.0 * 60.0 * 24.0;

fn nowJulianDate() f64 {
    const now: f64 = @floatFromInt(time.timestamp());
    log.debug("Now = {d:.0}", .{now});
    return now / seconds_in_day + unix_const;
}

fn reverseJulian(timestamp: f64) f64 {
    return (timestamp - unix_const) * seconds_in_day;
}

fn dateFromTimestamp(v: f64, timezone: i8) Time {
    const timestamp: c_longlong = @intFromFloat(v);
    const dt = cTime.gmtime(&timestamp);
    const hour: i8 = @intCast(dt.*.tm_hour);
    return Time{ .hour = @intCast(@rem(hour + timezone, 24)), .minute = @intCast(dt.*.tm_min) };
}

// https://en.wikipedia.org/wiki/Sunrise_equation#Complete_calculation_on_Earth
pub fn calculate(latitude: f64, longitude: f64, elevation: f64, timezone: i8) !SunInfo {
    const perihelion = 102.9372;
    const max_axial_tilt = math.degreesToRadians(23.4397);
    const latitude_rad = math.degreesToRadians(latitude);

    const julian_day: f64 = math.ceil(nowJulianDate() - noon_const + 0.0008);
    log.debug("Julian day = {d:.4}", .{julian_day});

    const mean_solar_time = julian_day - longitude / 360.0;
    log.debug("Mean solar time = {d:.4}", .{mean_solar_time});

    const solar_mean_anomaly = try math.mod(f64, 357.5291 + 0.98560028 * mean_solar_time, 360);
    const solar_mean_anomaly_rad = math.degreesToRadians(solar_mean_anomaly);
    log.debug("Solar mean anomaly = {d:.4}", .{solar_mean_anomaly});

    const equation_of_center = 1.9148 * math.sin(solar_mean_anomaly_rad) + 0.02 * math.sin(2 * solar_mean_anomaly_rad) + 0.0003 * math.sin(3 * solar_mean_anomaly_rad);
    log.debug("Equation of the center = {d:.4}", .{equation_of_center});

    const ecliptic_longitude = try math.mod(f64, solar_mean_anomaly + equation_of_center + 180 + perihelion, 360);
    const ecliptic_longitude_rad = math.degreesToRadians(ecliptic_longitude);
    log.debug("Ecliptic longitude = {d:.4}", .{ecliptic_longitude});

    const solar_transit = noon_const + mean_solar_time + 0.0053 * math.sin(solar_mean_anomaly_rad) - 0.0068 * math.sin(2 * ecliptic_longitude_rad);
    log.debug("Solar transit time = {d:.4}", .{solar_transit});

    const sin_d = math.sin(ecliptic_longitude_rad) * math.sin(max_axial_tilt);
    const cos_d = math.cos(math.asin(sin_d));

    const some_cos = (math.sin(math.degreesToRadians(-0.833 - 2.076 * math.sqrt(elevation) / 60.0)) - math.sin(latitude_rad) * sin_d) / (math.cos(latitude_rad) * cos_d);
    const hour_angle = math.radiansToDegrees(math.acos(some_cos));
    log.debug("Hour angle = {d:.4}", .{hour_angle});

    const solar_rise = reverseJulian(solar_transit - hour_angle / 360);
    log.debug("Sunrise = {d:.4}", .{solar_rise});
    const solar_set = reverseJulian(solar_transit + hour_angle / 360);
    log.debug("Sunset = {d:.4}", .{solar_set});

    return SunInfo{ .sunrise = dateFromTimestamp(solar_rise, timezone), .sunset = dateFromTimestamp(solar_set, timezone) };
}
