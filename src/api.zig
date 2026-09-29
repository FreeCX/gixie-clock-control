const std = @import("std");
const net = std.net;
const json = std.json;

const Websocket = @import("websocket.zig").Websocket;

const log = std.log.scoped(.api);

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
    // u10 должно хватить
    resCode: u16,
    cmdType: Type,
    cmdNum: Command,
    // TODO: тут не понятно в каком диапазоне значения
    data: ?i32 = null,
};

pub const Api = struct {
    socket: Websocket,

    pub fn init(host: []u8, port: u16, reader: *std.Io.Reader, writer: *std.Io.Writer) !Api {
        const socket = try Websocket.init(reader, writer);
        log.debug("-- handshake --", .{});
        try socket.handshake(host, port);
        return Api{ .socket = socket };
    }

    fn request(self: Api, cmd_type: Type, cmd: Command, value: ?i32) !void {
        var request_data = Request{
            .cmdType = cmd_type,
            .cmdNum = cmd,
            .cmdCtx = null,
        };
        if (value != null) {
            request_data.cmdCtx = Context{ .value = value.? };
        }

        log.debug("request: {any}", .{request_data});

        var json_buffer: [127]u8 = undefined;
        var json_writer = std.Io.Writer.fixed(&json_buffer);
        const fmt = json.fmt(
            request_data,
            .{ .emit_null_optional_fields = false },
        );
        try fmt.format(&json_writer);
        const request_bytes = json_buffer[0..json_writer.end];

        log.debug("json payload", .{});

        try self.socket.writeText(request_bytes);
    }

    fn response(self: Api, gpa: std.mem.Allocator) !json.Parsed(Response) {
        log.debug("read response", .{});
        const response_bytes = try self.socket.readText();

        const response_data = try json.parseFromSlice(
            Response,
            gpa,
            response_bytes,
            .{},
        );
        log.debug("response: {any}", .{response_data.value});

        return response_data;
    }

    // TODO: нормальный API
    pub fn get(self: Api, gpa: std.mem.Allocator, cmd: Command) !i32 {
        log.debug("-- read --", .{});

        // send command
        try self.request(.Get, cmd, null);

        // read response
        const response_data = try self.response(gpa);
        defer response_data.deinit();

        return response_data.value.data orelse return error.MissingData;
    }

    // TODO: нормальный API
    pub fn set(self: Api, gpa: std.mem.Allocator, cmd: Command, value: i32) !void {
        log.debug("-- write --", .{});

        // send command
        try self.request(.Set, cmd, value);

        // read response
        const response_data = try self.response(gpa);
        defer response_data.deinit();
    }
};
