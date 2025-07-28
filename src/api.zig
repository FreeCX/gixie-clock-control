const std = @import("std");
const log = std.log;
const net = std.net;
const json = std.json;
const Websocket = @import("websocket.zig").Websocket;

pub const Type = enum(u2) {
    Get = 0,
    Set = 1,
};

pub const Command = enum(u8) {
    Brightness = 14,
};

pub const Request = struct {
    cmdType: Type,
    cmdNum: Command,
    cmdCtx: ?u8 = null,

    // TOOD: пока делаю так, т.к. не понял как серилизовывать значения, а не строки
    pub fn jsonStringify(self: *const Request, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("cmdType");
        try jws.print("{d}", .{@intFromEnum(self.cmdType)});
        try jws.objectField("cmdNum");
        try jws.print("{d}", .{@intFromEnum(self.cmdNum)});
        if (self.cmdCtx != null) {
            try jws.objectField("cmdCtx");
            try jws.print("{d}", .{self.cmdCtx.?});
        }
        try jws.endObject();
    }
};

pub const Response = struct {
    // TODO: это обычный код из HTTP
    resCode: u16,
    cmdType: Type,
    cmdNum: Command,
    // TODO: тут не понятно в каком диапазоне значения
    data: i32,
};

pub const Api = struct {
    stream: Websocket,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(address: net.Address, allocator: std.mem.Allocator) !Self {
        const stream = try Websocket.init(address, allocator);

        log.debug("-- handshake --", .{});
        try stream.handshake();

        return Self{ .stream = stream, .allocator = allocator };
    }

    fn request(self: Self, cmd_type: Type, cmd: Command, value: ?u8) !void {
        const request_data = Request{ .cmdType = cmd_type, .cmdNum = cmd, .cmdCtx = value };
        const request_bytes = try json.stringifyAlloc(self.allocator, request_data, .{});
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

        return response_data.value.data;
    }

    // TODO: нормальный API
    pub fn set(self: Api, cmd: Command, value: u8) !void {
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
