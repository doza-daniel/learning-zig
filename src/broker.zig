const std = @import("std");
const Io = std.Io;

const Server = @import("Server");
const kafka = @import("kafka");

pub fn main(init: std.process.Init) !void {
    const srv: Server = .{
        .host = "0.0.0.0",
        .port = 8080,
        .handler = kafka.handler,
    };
    try srv.Start(init.io, init.gpa);
}
