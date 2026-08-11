const std = @import("std");

const mem = std.mem;
const net = std.Io.net;

const Reader = @import("Reader.zig");
const Writer = @import("Writer.zig");
const RequestHeader = @import("RequestHeader.zig");
const ResponseHeader = @import("ResponseHeader.zig");
const ApiVersionsRequest = @import("ApiVersionsRequest.zig");
const ApiVersionsResponse = @import("ApiVersionsResponse.zig");
const MetadataRequest = @import("MetadataRequest.zig");
const MetadataResponse = @import("MetadataResponse.zig");

pub fn kafka(alloc: mem.Allocator, io: std.Io, stream: net.Stream) !void {
    defer stream.close(io);

    var buffer: [2096]u8 = undefined;

    var p = stream.reader(io, &buffer);
    const stream_reader = &p.interface;

    while (true) {
        const requestBody = readRawRequest(alloc, stream_reader) catch |err| {
            if (err == error.EndOfStream) {
                return;
            }
            return err;
        };
        defer alloc.free(requestBody);

        std.debug.print("requestBody: {x}\n", .{requestBody});
        var reader: Reader = .{ .src = requestBody };

        var reqHeader = RequestHeader{};
        try reqHeader.read(&reader, alloc);
        defer reqHeader.deinit(alloc);

        handleRequest(alloc, io, reqHeader, stream, &reader) catch |err| {
            std.debug.print("error while handing conn: {any}\n", .{err});
            return;
        };
    }
}

fn handleRequest(alloc: mem.Allocator, io: std.Io, req_header: RequestHeader, stream: net.Stream, reader: *Reader) !void {
    std.debug.print("{f}\n", .{std.json.fmt(req_header, .{})});
    switch (req_header.request_api_key) {
        18 => try handleApiVersionsRequest(alloc, io, stream, reader, req_header.correlation_id),
        3 => try handleMetadataRequest(alloc, io, stream, reader, req_header.correlation_id, req_header.request_api_version),
        else => return error.UnknownOp,
    }
}

fn handleApiVersionsRequest(alloc: mem.Allocator, io: std.Io, stream: net.Stream, reader: *Reader, correlation_id: i32) !void {
    var apiVersionsReq = ApiVersionsRequest{};
    try apiVersionsReq.read(reader, alloc);
    defer apiVersionsReq.deinit(alloc);

    std.debug.print("{f}\n", .{std.json.fmt(apiVersionsReq, .{})});

    var w: Writer = .{};
    defer w.deinit(alloc);

    const respHeader: ResponseHeader = .{
        .correlation_id = correlation_id,
    };
    try respHeader.write(alloc, &w);

    const api_keys = [_]ApiVersionsResponse.ApiVersion{
        .{
            .api_key = 18,
            .min_version = 5,
            .max_version = 5,
        },
        .{
            .api_key = 3,
            .min_version = 13,
            .max_version = 13,
        },
    };
    const apiVersionsResp: ApiVersionsResponse = .{ .error_code = 0, .api_keys = &api_keys };
    try apiVersionsResp.write(alloc, &w);

    try writeRawResponse(io, stream, w.buf.items);
}

fn handleMetadataRequest(alloc: mem.Allocator, io: std.Io, stream: net.Stream, reader: *Reader, correlation_id: i32, version: i16) !void {
    var metadataReq = MetadataRequest{ .version = version };
    try metadataReq.read(reader, alloc);
    defer metadataReq.deinit(alloc);

    std.debug.print("{f}\n", .{std.json.fmt(metadataReq, .{})});

    const partitions = [_]MetadataResponse.MetadataResponsePartition{
        .{
            .error_code = 0,
            .partition_index = 0,
            .leader_id = 1,
            .leader_epoch = 320,
            .replica_nodes = &.{},
            .isr_nodes = &.{},
            .offline_replicas = &.{},
        },
        .{
            .error_code = 0,
            .partition_index = 1,
            .leader_id = 2,
            .leader_epoch = 320,
            .replica_nodes = &.{},
            .isr_nodes = &.{},
            .offline_replicas = &.{},
        },
    };

    const topics = [_]MetadataResponse.MetadataResponseTopic{
        .{
            .error_code = 0,
            .name = "my-topic",
            .topic_id = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 },
            .is_internal = false,
            .partitions = &partitions,
        },
    };

    const brokers = [_]MetadataResponse.MetadataResponseBroker{
        .{
            .host = "localhost",
            .port = 8080,
            .node_id = 1,
            .rack = "asdf",
        },
    };

    const metadataResp: MetadataResponse = .{
        .throttle_time_ms = 100,
        .brokers = &brokers,
        .cluster_id = "my-cluster",
        .controller_id = 1,
        .topics = &topics,
        .error_code = 0,
    };

    var w: Writer = .{};
    defer w.deinit(alloc);

    const respHeader: ResponseHeader = .{
        .correlation_id = correlation_id,
    };
    try respHeader.write(alloc, &w);
    try w.writeUvarint(alloc, 0);

    try metadataResp.write(alloc, &w);

    try writeRawResponse(io, stream, w.buf.items);
}

fn readRawRequest(alloc: mem.Allocator, stream_reader: *std.Io.Reader) ![]u8 {
    var size_buffer: [4]u8 = undefined;
    try stream_reader.readSliceEndian(u8, &size_buffer, .big);
    const size = mem.readInt(i32, &size_buffer, .big);

    const src = try alloc.alloc(u8, @intCast(size));

    try stream_reader.readSliceAll(src);

    return src;
}

fn writeRawResponse(io: std.Io, stream: net.Stream, rawResponse: []u8) !void {
    var buffer: [2096]u8 = undefined;

    var sw = stream.writer(io, &buffer);
    var stream_writer = &sw.interface;

    try stream_writer.writeInt(i32, @intCast(rawResponse.len), .big);
    const written = try stream_writer.write(rawResponse);

    if (written != rawResponse.len) {
        return error.NotEnoughWritten;
    }
    try stream_writer.flush();
}
