const std = @import("std");

const mem = std.mem;
const net = std.Io.net;

const Reader = @import("Reader.zig");
const Writer = @import("Writer.zig");
const RequestHeader = @import("RequestHeader.zig");
const ResponseHeader = @import("ResponseHeader.zig");
const ApiVersionsRequest = @import("ApiVersionsRequest.zig");
const ApiVersionsResponse = @import("ApiVersionsResponse.zig");

pub fn kafka(alloc: mem.Allocator, io: std.Io, stream: net.Stream) !void {
    defer stream.close(io);

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
