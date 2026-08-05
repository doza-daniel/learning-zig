const std = @import("std");

const net = std.Io.net;
const mem = std.mem;
const http = std.http;

pub fn main(init: std.process.Init) !void {
    const addr: net.IpAddress = try .parseIp4("0.0.0.0", 8080);

    var netSrv = try addr.listen(init.io, .{ .reuse_address = true });
    defer netSrv.deinit(init.io);

    while (true) {
        const stream = try netSrv.accept(init.io);
        defer stream.close(init.io);
        if (true) {
            return kafka(init.gpa, init.io, stream);
        }

        var read_buffer: [4098]u8 = undefined;
        var write_buffer: [4098]u8 = undefined;

        var r = stream.reader(init.io, &read_buffer);
        var w = stream.writer(init.io, &write_buffer);

        var conn = http.Server.init(&r.interface, &w.interface);
        var req = try conn.receiveHead();

        if (req.head.content_length orelse 0 == 0) {
            try req.respond("missing body", .{ .status = .bad_request });
            continue;
        }

        var br = http.Reader.bodyReader(&conn.reader, &read_buffer, req.head.transfer_encoding, req.head.content_length);

        br.readSliceAll(&read_buffer) catch |err| {
            switch (err) {
                error.ReadFailed => return err,
                error.EndOfStream => {},
            }
        };

        const body = read_buffer[0..req.head.content_length.?];

        const response = try std.fmt.allocPrint(init.gpa, "hello {s}\n", .{body});
        defer init.gpa.free(response);

        try req.respond(response, .{ .status = .ok });
    }
}

fn kafka(alloc: mem.Allocator, io: std.Io, stream: net.Stream) !void {
    var buffer: [2096]u8 = undefined;
    var p = stream.reader(io, &buffer);
    var stream_reader = &p.interface;

    var size_buffer: [4]u8 = undefined;
    try stream_reader.readSliceEndian(u8, &size_buffer, .big);
    const size = mem.readInt(i32, &size_buffer, .big);

    const src = try alloc.alloc(u8, @intCast(size));
    defer alloc.free(src);

    try stream_reader.readSliceAll(src);

    var rr: reader = .{ .src = src };

    const api_key = rr.readInt(i16);
    const api_version = rr.readInt(i16);
    const correlation_id = rr.readInt(i32);
    const client_id = rr.readNullableString(alloc);

    std.debug.print("api_key: {d}; api_version:{d}; correlation_id: {d}; client_id: {s}\n", .{
        api_key,
        api_version,
        correlation_id,
        client_id orelse "null",
    });

    _ = try rr.readUvarint();

    const client_software_name = rr.readCompactString(alloc);
    defer alloc.free(client_software_name);
    const client_software_version = rr.readCompactString(alloc);
    defer alloc.free(client_software_version);

    std.debug.print("client_software_name: {s}; client_software_version: {s}\n", .{
        client_software_name,
        client_software_version,
    });

    if (client_id) |slice| {
        alloc.free(slice);
    }
}

const reader = struct {
    src: []u8,
    offset: usize = 0,

    pub fn readInt(self: *reader, T: type) T {
        const result = mem.readVarInt(T, self.src[self.offset .. self.offset + @sizeOf(T)], .big);
        self.offset += @sizeOf(T);
        return result;
    }

    pub fn readUvarint(self: *reader) !u32 {
        var result: u32 = 0;
        var shift: u5 = 0;
        for (self.src[self.offset..], 0..) |byte, i| {
            if (i == 4) {
                if (byte > 0x3F) {
                    return error.Overflow;
                }
            }

            self.offset += 1;

            result |= @as(u32, byte & 0x7F) << shift;
            if (byte < 0x80) {
                return result;
            }

            shift += 7;
        }
        return result;
    }

    pub fn readNullableString(
        self: *reader,
        alloc: mem.Allocator,
    ) ?[]const u8 {
        const len = self.readInt(i16);
        if (len < 0) {
            return null;
        }

        const s = self.src[self.offset .. self.offset + @as(usize, @intCast(len))];
        const x = alloc.dupe(u8, s) catch {
            return null;
        };

        self.offset += @as(usize, @intCast(len));
        return x;
    }

    pub fn readCompactString(self: *reader, alloc: mem.Allocator) []const u8 {
        const len = self.readUvarint() catch unreachable;
        if (len <= 1) {
            return "";
        }
        const x = alloc.dupe(u8, self.src[self.offset .. self.offset + len - 1]) catch "";
        self.offset += len - 1;
        return x;
    }
};

test "readUvarint:happy" {
    var in = [_]u8{ 0x96, 0x01 };
    const expect: u32 = 150;
    var x: reader = .{ .src = &in };
    const got = try x.readUvarint();
    try std.testing.expect(got == expect);
}

test "readUvarint:overflow" {
    var in = [_]u8{ 0xff, 0xff, 0xff, 0xff, 0x4f };
    var x: reader = .{ .src = &in };
    _ = x.readUvarint() catch |err| {
        try std.testing.expect(err == error.Overflow);
        return;
    };
    try std.testing.expect(false);
}

test "readUvarint:max_u32" {
    var in = [_]u8{ 0xff, 0xff, 0xff, 0xff, 0x3f };
    var x: reader = .{ .src = &in };
    const got = try x.readUvarint();
    try std.testing.expect(got == std.math.maxInt(u32));
}
