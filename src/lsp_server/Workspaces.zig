map: std.array_hash_map.String(*Workspace) = .empty,
mutex: std.Io.Mutex = .{},

pub fn get(self: *Workspaces, io: Io, uri: []const u8) !?*Workspace {
    self.mutex.lock(io);
    defer self.mutex.unlock(io);
    return self.map.get(uri);
}

pub fn getOrCreate(self: *Workspaces, s: *Server, uri: []const u8, enable_compilation: bool) !*Workspace {
    try self.mutex.lock(s.io);

    const gop = try self.map.getOrPut(uri);

    if (gop.found_existing) {
        const ws = gop.value_ptr.*;
        self.mutex.unlock(s.io);
        return ws;
    }

    gop.key_ptr.* = try s.allocator.dupe(u8, uri);
    const ws = try s.allocator.create(Workspace);
    errdefer s.allocator.destroy(ws);
    ws.* = .init(s, uri, false, enable_compilation);
    errdefer ws.deinit(s.allocator);
    gop.value_ptr.* = ws;

    self.mutex.unlock(s.io);

    try ws.configuration.reload(s, ws);
    return ws;
}

pub fn triggerCreate(self: *Workspaces, s: *Server, uri: []const u8, enable_compilation: bool) !void {
    _ = try std.Io.concurrent(s.io, getOrCreate, .{ self, s, uri, enable_compilation });
}

const Workspaces = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const lsp_server = @import("lsp-server");
const Server = lsp_server.Server;

const Workspace = @import("Workspace.zig");
