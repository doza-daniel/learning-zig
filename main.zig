const std = @import("std");

const Server = @import("Server.zig");

pub fn main(init: std.process.Init) !void {
    const srv: Server = .{
        .host = "0.0.0.0",
        .port = 8080,
        .handler = @import("kafka.zig").kafka,
    };
    try srv.Start(init.io, init.gpa);
}
