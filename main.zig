const std = @import("std");

const Reader = @import("Reader.zig");
const Writer = @import("Writer.zig");
const RequestHeader = @import("RequestHeader.zig");
const ResponseHeader = @import("ResponseHeader.zig");
const ApiVersionsRequest = @import("ApiVersionsRequest.zig");
const ApiVersionsResponse = @import("ApiVersionsResponse.zig");

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
            try kafka(init.gpa, init.io, stream);
        } else {
            try http_server(init.gpa, init.io, stream);
        }
    }
}

fn kafka(alloc: mem.Allocator, io: std.Io, stream: net.Stream) !void {
    var buffer: [2096]u8 = undefined;

    var p = stream.reader(io, &buffer);
    var stream_reader = &p.interface;

    while (true) {
        var size_buffer: [4]u8 = undefined;
        try stream_reader.readSliceEndian(u8, &size_buffer, .big);
        const size = mem.readInt(i32, &size_buffer, .big);

        const src = try alloc.alloc(u8, @intCast(size));
        defer alloc.free(src);

        try stream_reader.readSliceAll(src);

        var reader: Reader = .{ .src = src };

        var header = RequestHeader{};
        try header.read(&reader, alloc);
        defer header.deinit(alloc);

        var apiVersionsReq = ApiVersionsRequest{};
        try apiVersionsReq.read(&reader, alloc);
        defer apiVersionsReq.deinit(alloc);

        std.debug.print("{f}\n{f}\n", .{
            std.json.fmt(header, .{}),
            std.json.fmt(apiVersionsReq, .{}),
        });

        var w: Writer = .{};
        defer w.deinit(alloc);

        const respHeader: ResponseHeader = .{
            .correlation_id = header.correlation_id,
        };
        try respHeader.write(alloc, &w);

        const api_keys = [_]ApiVersionsResponse.ApiVersion{
            .{
                .api_key = 18,
                .min_version = 4,
                .max_version = 4,
            },
            .{
                .api_key = 3,
                .min_version = 4,
                .max_version = 4,
            },
        };
        const apiVersionsResp: ApiVersionsResponse = .{ .error_code = 0, .api_keys = &api_keys };
        try apiVersionsResp.write(alloc, &w);

        var sw = stream.writer(io, &buffer);
        var stream_writer = &sw.interface;

        try stream_writer.writeInt(i32, @intCast(w.buf.items.len), .big);
        const written = try stream_writer.write(w.buf.items);

        if (written != w.buf.items.len) {
            return error.NotEnoughWritten;
        }
        try stream_writer.flush();
    }
}

fn http_server(alloc: mem.Allocator, io: std.Io, stream: net.Stream) !void {
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
