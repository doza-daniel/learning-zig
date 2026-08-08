const std = @import("std");

const net = std.Io.net;
const mem = std.mem;

const Server = @This();

host: []const u8,
port: u16,
handler: fn (alloc: mem.Allocator, io: std.Io, stream: net.Stream) anyerror!void,

pub fn Start(self: Server, io: std.Io, alloc: mem.Allocator) !void {
    const addr: net.IpAddress = try .parseIp4(self.host, self.port);

    var netSrv = try addr.listen(io, .{ .reuse_address = true });
    defer netSrv.deinit(io);

    while (true) {
        const stream = try netSrv.accept(io);
        try self.handler(alloc, io, stream);
    }
}
