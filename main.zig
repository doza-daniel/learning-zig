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

    const api_key = try rr.readInt(i16);
    const api_version = try rr.readInt(i16);
    const correlation_id = try rr.readInt(i32);

    const client_id = try rr.readNullableString(alloc);
    defer maybeFree(alloc, client_id);

    std.debug.print("api_key: {d}; api_version:{d}; correlation_id: {d}; client_id: {s}\n", .{
        api_key,
        api_version,
        correlation_id,
        client_id orelse "null",
    });

    // skip tags
    if (try rr.readUvarint() > 0) {
        return error.UnexpectedTags;
    }

    const client_software_name = try rr.readCompactString(alloc);
    defer alloc.free(client_software_name);
    const client_software_version = try rr.readCompactString(alloc);
    defer alloc.free(client_software_version);

    // skip tags
    if (try rr.readUvarint() > 0) {
        return error.UnexpectedTags;
    }

    std.debug.print("client_software_name: {s}; client_software_version: {s}\n", .{
        client_software_name,
        client_software_version,
    });
}

fn maybeFree(alloc: mem.Allocator, maybe: ?[]const u8) void {
    if (maybe) |memory| {
        alloc.free(memory);
    }
}

const reader = struct {
    src: []u8,

    pub fn readInt(self: *reader, T: type) !T {
        if (self.src.len < @sizeOf(T)) {
            return error.UnexpectedEOF;
        }
        const result = mem.readInt(T, self.src[0..@sizeOf(T)], .big);
        self.src = self.src[@sizeOf(T)..];
        return result;
    }

    pub fn readUvarint(self: *reader) !u32 {
        var result: u32 = 0;
        var shift: u5 = 0;
        for (self.src, 0..) |byte, i| {
            if (i == 4) {
                if (byte > 0x3F) {
                    return error.Overflow;
                }
            }

            result |= @as(u32, byte & 0x7F) << shift;
            if (byte < 0x80) {
                self.src = self.src[i + 1 ..];
                return result;
            }

            shift += 7;
        }
        return error.UnexpectedEOF;
    }

    pub fn readNullableString(
        self: *reader,
        alloc: mem.Allocator,
    ) !?[]const u8 {
        const num = try self.readInt(i16);
        if (num < 0) {
            return null;
        }

        const len = @as(usize, @intCast(num));

        if (self.src.len < len) {
            return error.UnexpectedEOF;
        }

        const str = try alloc.dupe(u8, self.src[0..len]);
        self.src = self.src[len..];
        return str;
    }

    pub fn readCompactString(self: *reader, alloc: mem.Allocator) ![]const u8 {
        const len = try self.readUvarint();
        if (len <= 1) {
            return "";
        }
        if (self.src.len < len - 1) {
            return error.UnexpectedEOF;
        }
        const x = try alloc.dupe(u8, self.src[0 .. len - 1]);
        self.src = self.src[len - 1 ..];
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

test "readUvarint:unexpected_eof" {
    var in = [_]u8{0xff};
    var x: reader = .{ .src = &in };
    _ = x.readUvarint() catch |err| {
        try std.testing.expect(err == error.UnexpectedEOF);
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

test "readNullableString:null" {
    var in = [_]u8{ 0xff, 0xff };
    var x: reader = .{ .src = &in };
    const got = x.readNullableString(std.testing.allocator) catch {
        try std.testing.expect(false);
        return;
    };
    try std.testing.expect(got == null);
}

test "readNullableString:empty" {
    var in = [_]u8{ 0x00, 0x00 };
    var x: reader = .{ .src = &in };
    const got = x.readNullableString(std.testing.allocator) catch {
        try std.testing.expect(false);
        return;
    };
    if (got) |str| {
        try std.testing.expect(str.len == 0);
        return;
    }
    try std.testing.expect(false);
}

test "readNullableString:hello" {
    var in = [_]u8{ 0x00, 0x05, 'h', 'e', 'l', 'l', 'o' };
    var x: reader = .{ .src = &in };
    const got = x.readNullableString(std.testing.allocator) catch {
        try std.testing.expect(false);
        return;
    };
    if (got) |str| {
        try std.testing.expect(mem.eql(u8, str, "hello"));
        std.testing.allocator.free(str);
        return;
    }
    try std.testing.expect(false);
}

test "readNullableString:alloc_fail" {
    var in = [_]u8{ 0x00, 0x05, 'h', 'e', 'l', 'l', 'o' };
    var x: reader = .{ .src = &in };
    _ = x.readNullableString(std.testing.failing_allocator) catch |err| {
        try std.testing.expect(err == error.OutOfMemory);
        return;
    };
    try std.testing.expect(false);
}
