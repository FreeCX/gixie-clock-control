// https://datatracker.ietf.org/doc/html/rfc6455

const std = @import("std");
const log = std.log;
const mem = std.mem;
const net = std.net;

pub const Opcode = enum(u4) {
    Continuation = 0,
    Text = 1,
    Binary = 2,
    Reserved1 = 3,
    Reserved2 = 4,
    Reserved3 = 5,
    Reserved4 = 6,
    Reserved5 = 7,
    Close = 8,
    Ping = 9,
    Pong = 10,
    Reserved6 = 11,
    Reserved7 = 12,
    Reserved8 = 13,
    Reserved9 = 14,
    Reserved10 = 15,
};
// из-за порядка укладки пришлось переставить поля
pub const Frame = packed struct {
    opcode: Opcode,
    rsv3: bool = false,
    rsv2: bool = false,
    rsv1: bool = false,
    fin: bool = true,
    payload_len: u7 = 0,
    mask: bool = false,
};

const buffer_size = 128;

pub const Websocket = struct {
    stream: net.Stream,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(address: net.Address, allocator: std.mem.Allocator) !Self {
        const api = Self{
            .stream = try net.tcpConnectToAddress(address),
            .allocator = allocator,
        };
        return api;
    }

    fn allocRead(self: Self, len: usize) ![]u8 {
        const buffer = try self.allocator.alloc(u8, len);
        _ = try self.stream.read(buffer);
        return buffer;
    }

    pub fn readFrame(self: Self) !Frame {
        const frame = try self.stream.reader().readStruct(Frame);
        const frame_bytes: [2]u8 = @bitCast(frame);
        log.debug("read frame: {any} | {any}", .{ frame_bytes, frame });
        return frame;
    }

    pub fn sendFrame(self: Self, frame: Frame) !void {
        const frame_bytes: [2]u8 = @bitCast(frame);
        log.debug("send frame: {any} | {any}", .{ frame_bytes, frame });
        _ = try self.stream.write(&frame_bytes);
    }

    pub fn handshake(self: Self) !void {
        const http_upgrade =
            "GET / HTTP/1.1\r\n" ++
            "Host: 192.168.88.97:81\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Sec-WebSocket-Version: 13\r\n" ++
            "Sec-WebSocket-Key: w73/mpTYTn75oPFTajvs4Q==\r\n" ++
            "\r\n";

        log.debug("send http upgrade:\n{s}", .{http_upgrade});
        try self.stream.writeAll(http_upgrade);

        const buffer = try self.allocator.alloc(u8, buffer_size);
        defer self.allocator.free(buffer);

        // http response
        var reader = self.stream.reader();
        while (true) {
            const line = try reader.readUntilDelimiter(buffer, '\n');
            log.debug("read {d} bytes: {s}", .{ line.len, line });
            if (mem.eql(u8, line, "\r")) {
                break;
            }
        }

        // ping
        const first_frame = try self.readFrame();
        if (first_frame.opcode == .Ping) {
            try self.sendFrame(Frame{ .opcode = .Pong });
        }

        // text
        const second_frame = try self.readFrame();
        if (second_frame.payload_len > 0) {
            const payload = try self.allocRead(second_frame.payload_len);
            defer self.allocator.free(payload);
            log.debug("payload: {s}", .{payload});
        }
    }

    pub fn writeText(self: Self, payload: []const u8) !void {
        try self.sendFrame(Frame{ .opcode = .Text, .payload_len = @intCast(payload.len) });
        log.debug("payload: {s}", .{payload});
        _ = try self.stream.write(payload);
    }

    pub fn readText(self: Self) ![]u8 {
        const frame = try self.readFrame();
        const payload = try self.allocRead(frame.payload_len);
        log.debug("payload: {s}", .{payload});
        return payload;
    }

    pub fn close(self: Self) !void {
        try self.sendFrame(Frame{ .opcode = .Close });

        const frame = try self.readFrame();
        if (frame.payload_len > 0) {
            const payload = try self.allocator.alloc(u8, frame.payload_len);
            defer self.allocator.free(payload);

            _ = try self.stream.read(payload);
            log.debug("payload: {any}", .{payload});
        }

        self.stream.close();
    }
};
