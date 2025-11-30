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

// low budget websocket
pub const Websocket = struct {
    reader: *std.io.Reader,
    writer: *std.io.Writer,

    const Self = @This();

    pub fn init(reader: *std.io.Reader, writer: *std.io.Writer) !Self {
        return Self{
            .reader = reader,
            .writer = writer,
        };
    }

    fn readFrame(self: Self) !Frame {
        const frame = try self.reader.takeStruct(Frame, .little);
        log.debug("read frame: {any}", .{frame});
        return frame;
    }

    fn sendFrame(self: Self, frame: Frame) !void {
        log.debug("write frame: {any}", .{frame});
        _ = try self.writer.writeStruct(frame, .little);
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
        var http_upgrade_buffer: [160]u8 = undefined;
        const http_upgrade = try fmt.bufPrint(&http_upgrade_buffer, format, .{ host, port });

        log.debug("send http upgrade:\n{s}", .{http_upgrade});
        _ = try self.writer.write(http_upgrade);
        try self.writer.flush();

        // http response
        while (true) {
            const line = try self.reader.takeDelimiterInclusive('\n');
            log.debug("read {d} bytes: `{s}\\r\\n`", .{ line.len, mem.trimRight(u8, line, "\r\n") });
            if (mem.eql(u8, line, "\r\n")) {
                break;
            }
        }

        // ping
        const first_frame = try self.readFrame();
        if (first_frame.opcode == .Ping) {
            try self.sendFrame(Frame{ .opcode = .Pong });
            try self.writer.flush();
        }

        // text: Connected
        const second_frame = try self.readFrame();
        if (second_frame.payload_len > 0) {
            const payload = try self.reader.take(second_frame.payload_len);
            log.debug("read payload: {s}", .{payload});
        }
    }

    pub fn writeText(self: Self, payload: []const u8) !void {
        try self.sendFrame(Frame{ .opcode = .Text, .payload_len = @intCast(payload.len) });
        log.debug("write payload: {s}", .{payload});
        _ = try self.writer.write(payload);
        try self.writer.flush();
    }

    pub fn readText(self: Self) ![]u8 {
        const frame = try self.readFrame();
        const payload = try self.reader.take(frame.payload_len);
        log.debug("read payload: {s}", .{payload});
        return payload;
    }
};
