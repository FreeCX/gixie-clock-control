// https://datatracker.ietf.org/doc/html/rfc6455

const std = @import("std");
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
const net = std.net;

pub const Opcode = enum(u4) {
    Continuation = 0,
    Text = 1,
    Binary = 2,
    _Reserved1 = 3,
    _Reserved2 = 4,
    _Reserved3 = 5,
    _Reserved4 = 6,
    _Reserved5 = 7,
    Close = 8,
    Ping = 9,
    Pong = 10,
    _Reserved6 = 11,
    _Reserved7 = 12,
    _Reserved8 = 13,
    _Reserved9 = 14,
    _Reserved10 = 15,
};
// из-за порядка укладки пришлось переставить поля
pub const Frame = packed struct {
    // bits 4-7
    opcode: Opcode,
    // bit 3
    rsv3: bool = false,
    // bit 2
    rsv2: bool = false,
    // bit 1
    rsv1: bool = false,
    // bit 0
    fin: bool = true,
    // bit 9-15
    payload_len: u7 = 0,
    // bit 8
    mask: bool = false,
};

const http_upgrade_size = 160;
const buffer_size = 128;

// low budget websocket
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

    pub fn handshake(self: Self, host: []const u8, port: u16) !void {
        const format =
            "GET / HTTP/1.1\r\n" ++
            "Host: {s}:{d}\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Sec-WebSocket-Version: 13\r\n" ++
            // we don't care
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
            "\r\n";
        const tmp = try self.allocator.alloc(u8, http_upgrade_size);
        defer self.allocator.free(tmp);
        const http_upgrade = try fmt.bufPrint(tmp, format, .{host, port});

        log.debug("send http upgrade:\n{s}", .{http_upgrade});
        try self.stream.writeAll(http_upgrade);

        // http response
        const buffer = try self.allocator.alloc(u8, buffer_size);
        defer self.allocator.free(buffer);
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

        // text: Connected
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
