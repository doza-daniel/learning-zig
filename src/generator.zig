const std = @import("std");

const generator = @import("generator");

pub fn main(init: std.process.Init) !void {
    var read_buffer: [4096]u8 = undefined;
    var in = std.Io.File.stdin().reader(init.io, &read_buffer);

    var write_buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &write_buffer);
    defer out.flush() catch @panic("flush failed");

    try generator.do(init.gpa, &in.interface, &out.interface);
}
