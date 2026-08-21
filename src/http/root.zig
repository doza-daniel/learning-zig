const std = @import("std");

const net = std.Io.net;
const mem = std.mem;
const http = std.http;

pub fn handler(alloc: mem.Allocator, io: std.Io, stream: net.Stream) !void {
    var read_buffer: [4098]u8 = undefined;
    var write_buffer: [4098]u8 = undefined;

    var r = stream.reader(io, &read_buffer);
    var w = stream.writer(io, &write_buffer);

    var conn = http.Server.init(&r.interface, &w.interface);
    var req = try conn.receiveHead();

    if (req.head.content_length orelse 0 == 0) {
        try req.respond("missing body", .{ .status = .bad_request });
        return;
    }

    var br = http.Reader.bodyReader(&conn.reader, &read_buffer, req.head.transfer_encoding, req.head.content_length);

    br.readSliceAll(&read_buffer) catch |err| {
        switch (err) {
            error.ReadFailed => return err,
            error.EndOfStream => {},
        }
    };

    const body = read_buffer[0..req.head.content_length.?];

    const response = try std.fmt.allocPrint(alloc, "hello {s}\n", .{body});
    defer alloc.free(response);

    try req.respond(response, .{ .status = .ok });
}
