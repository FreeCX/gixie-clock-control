const std = @import("std");
const log = std.log;
const net = std.net;
const json = std.json;
const Websocket = @import("websocket.zig").Websocket;

const Type = enum(u2) {
    Get = 0,
    Set = 1,

    pub fn jsonStringify(self: *const Type, jws: anytype) !void {
        try jws.print("{d}", .{@intFromEnum(self.*)});
    }
};

const Command = enum(u8) {
    Brightness = 14,

    pub fn jsonStringify(self: *const Command, jws: anytype) !void {
        try jws.print("{d}", .{@intFromEnum(self.*)});
    }
};

const Context = struct {
    value: i32,
};

const Request = struct {
    cmdType: Type,
    cmdNum: Command,
    cmdCtx: ?Context = null,
};

const Response = struct {
    // TODO: это обычный код из HTTP
    resCode: u16,
    cmdType: Type,
    cmdNum: Command,
    // TODO: тут не понятно в каком диапазоне значения
    data: ?i32 = null,
};

pub const Api = struct {
    stream: Websocket,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(host: []const u8, port: u16, allocator: std.mem.Allocator) !Self {
        const address = try net.Address.parseIp4(host, port);
        const stream = try Websocket.init(address, allocator);

        log.debug("-- handshake --", .{});
        try stream.handshake(host, port);

        return Self{ .stream = stream, .allocator = allocator };
    }

    fn request(self: Self, cmd_type: Type, cmd: Command, value: ?i32) !void {
        var request_data = Request{ .cmdType = cmd_type, .cmdNum = cmd, .cmdCtx = null };
        if (value != null) {
            request_data.cmdCtx = Context {.value = value.?};
        }

        const request_bytes = try json.stringifyAlloc(self.allocator, request_data, .{ .emit_null_optional_fields = false });
        defer self.allocator.free(request_bytes);
        log.debug("request: {any}", .{ request_data });
        try self.stream.writeText(request_bytes);
    }

    fn response(self: Self) !json.Parsed(Response) {
        const response_bytes = try self.stream.readText();
        defer self.allocator.free(response_bytes);
        const response_data = try json.parseFromSlice(Response, self.allocator, response_bytes, .{});
        log.debug("response: {any}", .{ response_data.value });
        return response_data;
    }

    // TODO: нормальный API
    pub fn get(self: Self, cmd: Command) !i32 {
        log.debug("-- read --", .{});

        // send command
        try self.request(.Get, cmd, null);

        // read response
        const response_data = try self.response();
        defer response_data.deinit();

        return response_data.value.data.?;
    }

    // TODO: нормальный API
    pub fn set(self: Api, cmd: Command, value: i32) !void {
        log.debug("-- write --", .{});

        // send command
        try self.request(.Set, cmd, value);

        // read response
        const response_data = try self.response();
        defer response_data.deinit();
    }

    pub fn deinit(self: Api) void {
        log.debug("-- close --", .{});
        // TODO: пока просто игнорим если есть ошибка
        self.stream.close() catch return;
    }
};
