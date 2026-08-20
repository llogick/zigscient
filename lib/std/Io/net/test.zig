const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const mem = std.mem;
const testing = std.testing;
const Allocator = std.mem.Allocator;

test "parse and render IP addresses at comptime" {
    comptime {
        const ipv6addr = net.IpAddress.parse("::1", 0) catch unreachable;
        try testing.expectFmt("[::1]:0", "{f}", .{ipv6addr});

        const ipv4addr = net.IpAddress.parse("127.0.0.1", 0) catch unreachable;
        try testing.expectFmt("127.0.0.1:0", "{f}", .{ipv4addr});

        try testing.expectError(error.ParseFailed, net.IpAddress.parse("::123.123.123.123", 0));
        try testing.expectError(error.ParseFailed, net.IpAddress.parse("127.01.0.1", 0));
    }
}

test "format IPv6 address with no zero runs" {
    const addr = try net.IpAddress.parseIp6("2001:db8:1:2:3:4:5:6", 0);
    try testing.expectFmt("[2001:db8:1:2:3:4:5:6]:0", "{f}", .{addr});
}

test "parse IPv6 addresses and check compressed form" {
    try testing.expectFmt("[2001:db8::1:0:0:2]:0", "{f}", .{
        try net.IpAddress.parseIp6("2001:0db8:0000:0000:0001:0000:0000:0002", 0),
    });
    try testing.expectFmt("[2001:db8::1:2]:0", "{f}", .{
        try net.IpAddress.parseIp6("2001:0db8:0000:0000:0000:0000:0001:0002", 0),
    });
    try testing.expectFmt("[2001:db8:1:0:1::2]:0", "{f}", .{
        try net.IpAddress.parseIp6("2001:0db8:0001:0000:0001:0000:0000:0002", 0),
    });
}

test "parse IPv6 address, check raw bytes" {
    const expected_raw: [16]u8 = .{
        0x20, 0x01, 0x0d, 0xb8, // 2001:db8
        0x00, 0x00, 0x00, 0x00, // :0000:0000
        0x00, 0x01, 0x00, 0x00, // :0001:0000
        0x00, 0x00, 0x00, 0x02, // :0000:0002
    };
    const addr = try net.IpAddress.parseIp6("2001:db8:0000:0000:0001:0000:0000:0002", 0);
    try testing.expectEqualSlices(u8, &expected_raw, &addr.ip6.bytes);
}

test "parse and render IPv6 addresses" {
    try testParseAndRenderIp6Address("FF01:0:0:0:0:0:0:FB", "ff01::fb");
    try testParseAndRenderIp6Address("FF01::Fb", "ff01::fb");
    try testParseAndRenderIp6Address("::1", "::1");
    try testParseAndRenderIp6Address("::", "::");
    try testParseAndRenderIp6Address("1::", "1::");
    try testParseAndRenderIp6Address("2001:db8::", "2001:db8::");
    try testParseAndRenderIp6Address("::1234:5678", "::1234:5678");
    try testParseAndRenderIp6Address("2001:db8::1234:5678", "2001:db8::1234:5678");
    try testParseAndRenderIp6Address("FF01::FB%1234", "ff01::fb%1234");
    try testParseAndRenderIp6Address("::ffff:123.5.123.5", "::ffff:123.5.123.5");
    try testParseAndRenderIp6Address("ff01::fb%12345678901234", "ff01::fb%12345678901234");
}

fn testParseAndRenderIp6Address(input: []const u8, expected_output: []const u8) !void {
    var buffer: [100]u8 = undefined;
    const parsed = net.Ip6Address.Unresolved.parse(input);
    const actual_printed = try std.fmt.bufPrint(&buffer, "{f}", .{parsed.success});
    try testing.expectEqualStrings(expected_output, actual_printed);
}

test "IPv6 address parse failures" {
    try testing.expectError(error.ParseFailed, net.IpAddress.parseIp6(":::", 0));

    const Unresolved = net.Ip6Address.Unresolved;

    try testing.expectEqual(Unresolved.Parsed{ .invalid_byte = 2 }, Unresolved.parse(":::"));
    try testing.expectEqual(Unresolved.Parsed{ .overflow = 4 }, Unresolved.parse("FF001::FB"));
    try testing.expectEqual(Unresolved.Parsed{ .invalid_byte = 9 }, Unresolved.parse("FF01::Fb:zig"));
    try testing.expectEqual(Unresolved.Parsed{ .junk_after_end = 19 }, Unresolved.parse("FF01:0:0:0:0:0:0:FB:"));
    try testing.expectEqual(Unresolved.Parsed.incomplete, Unresolved.parse("FF01:"));
    try testing.expectEqual(Unresolved.Parsed{ .invalid_byte = 5 }, Unresolved.parse("::123.123.123.123"));
    try testing.expectEqual(Unresolved.Parsed.incomplete, Unresolved.parse("1"));
    try testing.expectEqual(Unresolved.Parsed.incomplete, Unresolved.parse("ff01::fb%"));
}

test "invalid but parseable IPv6 scope ids" {
    if (builtin.os.tag != .linux and builtin.os.tag != .windows and comptime !builtin.os.tag.isDarwin()) return error.SkipZigTest;

    const io = testing.io;

    try testing.expectError(error.InterfaceNotFound, net.IpAddress.resolveIp6(io, "ff01::fb%123s45678901234", 0));
}

test "oversized IPv6 scope id" {
    const long_scope: [256]u8 = @splat('a');
    try testing.expectError(error.ParseFailed, net.IpAddress.resolveIp6(testing.io, "ff01::fb%" ++ &long_scope, 0));
}

test "parse and render IPv4 addresses" {
    try testIp4ParseAndRender("0.0.0.0");
    try testIp4ParseAndRender("255.255.255.255");
    try testIp4ParseAndRender("1.2.3.4");
    try testIp4ParseAndRender("123.255.0.91");
    try testIp4ParseAndRender("127.0.0.1");

    try testing.expectError(error.Overflow, net.IpAddress.parseIp4("256.0.0.1", 0));
    try testing.expectError(error.InvalidCharacter, net.IpAddress.parseIp4("x.0.0.1", 0));
    try testing.expectError(error.InvalidEnd, net.IpAddress.parseIp4("127.0.0.1.1", 0));
    try testing.expectError(error.Incomplete, net.IpAddress.parseIp4("127.0.0.", 0));
    try testing.expectError(error.InvalidCharacter, net.IpAddress.parseIp4("100..0.1", 0));
    try testing.expectError(error.NonCanonical, net.IpAddress.parseIp4("127.01.0.1", 0));
}

fn testIp4ParseAndRender(text: []const u8) !void {
    var buffer: [18]u8 = undefined;
    const addr = try net.IpAddress.parseIp4(text, 0);
    const rendered = try std.fmt.bufPrint(&buffer, "{f}", .{addr});
    const without_port = rendered[0 .. rendered.len - 2];
    try testing.expectEqualStrings(text, without_port);
}

test "resolve DNS" {
    const io = testing.io;

    // Resolve localhost, this should not fail.
    {
        const localhost_v4 = try net.IpAddress.parse("127.0.0.1", 80);
        const localhost_v6 = try net.IpAddress.parse("::1", 80);

        var canonical_name_buffer: [net.HostName.max_len]u8 = undefined;
        var results_buffer: [32]net.HostName.LookupResult = undefined;
        var results: Io.Queue(net.HostName.LookupResult) = .init(&results_buffer);

        net.HostName.lookup(try .init("localhost"), io, &results, .{
            .port = 80,
            .canonical_name_buffer = &canonical_name_buffer,
        }) catch |err| switch (err) {
            error.NetworkDown => return error.SkipZigTest,
            else => |e| return e,
        };

        var addresses_found: usize = 0;
        var found_canonical_name = false;

        while (results.getOne(io)) |result| switch (result) {
            .address => |address| {
                if (address.eql(&localhost_v4) or address.eql(&localhost_v6))
                    addresses_found += 1;
            },
            // We can't test the actual string here because it might be "localhost.localdomain"
            // or even the computer host name (as on Windows).
            .canonical_name => found_canonical_name = true,
        } else |err| switch (err) {
            error.Closed => {},
            error.Canceled => |e| return e,
        }

        try testing.expect(found_canonical_name);
        try testing.expect(addresses_found != 0);
    }

    {
        // The tests are required to work even when there is no Internet connection,
        // so some of these errors we must accept and skip the test.
        var canonical_name_buffer: [net.HostName.max_len]u8 = undefined;
        var results_buffer: [16]net.HostName.LookupResult = undefined;
        var results: Io.Queue(net.HostName.LookupResult) = .init(&results_buffer);

        net.HostName.lookup(try .init("example.com"), io, &results, .{
            .port = 80,
            .canonical_name_buffer = &canonical_name_buffer,
        }) catch |err| switch (err) {
            error.UnknownHostName => return error.SkipZigTest,
            error.NameServerFailure => return error.SkipZigTest,
            else => |e| return e,
        };

        while (results.getOne(io)) |result| switch (result) {
            .address => {},
            .canonical_name => {},
        } else |err| switch (err) {
            error.Closed => {},
            error.Canceled => |e| return e,
        }
    }
}

test "listen on a port, send bytes, receive bytes" {
    if (true) return error.SkipZigTest; // https://codeberg.org/ziglang/zig/issues/31388

    const io = testing.io;

    // Try only the IPv4 variant as some CI builders have no IPv6 localhost
    // configured.
    const localhost: net.IpAddress = .{ .ip4 = .loopback(0) };

    var server = localhost.listen(io, .{}) catch |err| switch (err) {
        error.NetworkDown => return error.SkipZigTest,
        else => |e| return e,
    };
    defer server.deinit(io);

    const S = struct {
        fn clientFn(server_address: net.IpAddress) !void {
            var stream = try server_address.connect(io, .{ .mode = .stream });
            defer stream.close(io);

            var stream_writer = stream.writer(io, &.{});
            try stream_writer.interface.writeAll("Hello world!");
        }
    };

    var client_task = io.concurrent(S.clientFn, .{server.socket.address}) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    defer client_task.cancel(io) catch {};

    var stream = try server.accept(io);
    defer stream.close(io);

    var buf: [16]u8 = undefined;
    var stream_reader = stream.reader(io, &.{});
    const n = try stream_reader.interface.readSliceShort(&buf);

    try testing.expectEqual(@as(usize, 12), n);
    try testing.expectEqualStrings("Hello world!", buf[0..n]);

    try client_task.await(io);
}

test "listen on an in use port" {
    const io = testing.io;

    const localhost: net.IpAddress = .{ .ip4 = .loopback(0) };

    var server1 = localhost.listen(io, .{ .reuse_address = true }) catch |err| switch (err) {
        error.NetworkDown => return error.SkipZigTest,
        else => |e| return e,
    };
    defer server1.deinit(io);

    var server2 = try server1.socket.address.listen(io, .{ .reuse_address = true });
    defer server2.deinit(io);
}

test "listen on a unix socket, send bytes, receive bytes" {
    if (builtin.os.tag == .windows) {
        // https://codeberg.org/ziglang/zig/issues/31499
        return error.SkipZigTest;
    }

    const io = testing.io;
    const gpa = testing.allocator;

    const socket_path = try generateFileName(gpa, io, "socket.unix");
    defer gpa.free(socket_path);

    const socket_addr = try net.UnixAddress.init(socket_path);
    defer Io.Dir.cwd().deleteFile(io, socket_path) catch {};

    var server = socket_addr.listen(io, .{}) catch |err| switch (err) {
        error.AddressFamilyUnsupported => return error.SkipZigTest,
        error.NetworkDown => return error.SkipZigTest,
        else => |e| return e,
    };
    defer server.socket.close(io);

    const S = struct {
        fn clientFn(path: []const u8) !void {
            const server_path: net.UnixAddress = try .init(path);
            var stream = try server_path.connect(io);
            defer stream.close(io);

            var stream_writer = stream.writer(io, &.{});
            try stream_writer.interface.writeAll("Hello world!");
        }
    };

    var client_task = io.concurrent(S.clientFn, .{socket_path}) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    defer client_task.cancel(io) catch {};

    var stream = try server.accept(io);
    defer stream.close(io);

    var buf: [16]u8 = undefined;
    var stream_reader = stream.reader(io, &.{});
    const n = try stream_reader.interface.readSliceShort(&buf);

    try testing.expectEqual(@as(usize, 12), n);
    try testing.expectEqualStrings("Hello world!", buf[0..n]);

    try client_task.await(io);
}

fn generateFileName(gpa: Allocator, io: Io, base_name: []const u8) ![]const u8 {
    const random_bytes_count = 12;
    const sub_path_len = comptime std.base64.url_safe.Encoder.calcSize(random_bytes_count);
    var random_bytes: [12]u8 = undefined;
    io.random(&random_bytes);
    var sub_path: [sub_path_len]u8 = undefined;
    _ = std.base64.url_safe.Encoder.encode(&sub_path, &random_bytes);
    return std.fmt.allocPrint(gpa, "{s}-{s}", .{ sub_path[0..], base_name });
}

test "decompress compressed DNS name" {
    const packet = &[_]u8{
        // Header section
        // ----------------------------------------------------------
        0x00, 0x00, // ID: 0
        0x81, 0x80, // Flags (QR:1, RCODE:0, etc.)
        0x00, 0x01, // QDCOUNT: 1 (Question Count)
        0x00, 0x01, // ANCOUNT: 1 (Answer Count)
        0x00, 0x00, // NSCOUNT: 0
        0x00, 0x00, // ARCOUNT: 0
        // ----------------------------------------------------------

        // Question section (12 byte offset)
        // ----------------------------------------------------------
        // QNAME: "www.ziglang.org"
        0x03, 'w', 'w', 'w', // label
        0x07, 'z', 'i', 'g', 'l', 'a', 'n', 'g', // label
        0x03, 'o', 'r', 'g', // label
        0x00, // null label
        0x00, 0x01, // QTYPE: A
        0x00, 0x01, // QCLASS: IN
        // ----------------------------------------------------------

        // Resource Record (Answer) (33 byte offset)
        // ----------------------------------------------------------
        0xc0, 0x0c, // NAME: pointer to 0x0c ("www.ziglang.org")
        0x00, 0x05, // TYPE: CNAME
        0x00, 0x01, // CLASS: IN
        0x00, 0x00, 0x01, 0x00, // TTL: 256 (seconds)
        0x00, 0x06, // RDLENGTH: 6 bytes

        // RDATA (45 byte offset): "target.ziglang.org" (compressed)
        0x06, 't', 'a', 'r', 'g', 'e', 't', // 6, "target"
        0xc0, 0x10, // pointer (0xc0 flag) to 0x10 byte offset ("ziglang.org")
        // ----------------------------------------------------------
    };

    // The start index of the CNAME RDATA is 45
    const cname_data_index = 45;
    var dest_buffer: [net.HostName.max_len]u8 = undefined;

    const n_consumed, const result = try net.HostName.expand(
        packet,
        cname_data_index,
        &dest_buffer,
    );
    try testing.expectEqual(packet.len - cname_data_index, n_consumed);
    try testing.expectEqualStrings("target.ziglang.org", result.bytes);
}

test "cancel accept" {
    const io = testing.io;
    const localhost: net.IpAddress = .{ .ip4 = .loopback(0) };

    var server = localhost.listen(io, .{}) catch |err| switch (err) {
        error.NetworkDown => return error.SkipZigTest,
        else => |e| return e,
    };
    defer server.deinit(io);

    var accept = io.concurrent(std.Io.net.Server.accept, .{ &server, io }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    defer if (accept.cancel(io)) |stream| stream.close(io) else |_| {};

    try io.sleep(.fromNanoseconds(1), .awake);
}

test "UDP send and receive" {
    const io = testing.io;
    const localhost: net.IpAddress = .{ .ip4 = .loopback(0) };

    const recv_sock = localhost.bind(io, .{ .mode = .dgram }) catch |err| switch (err) {
        error.NetworkDown => return error.SkipZigTest,
        else => |e| return e,
    };
    defer recv_sock.close(io);
    const send_sock = try localhost.bind(io, .{ .mode = .dgram });
    defer send_sock.close(io);

    const send_data: [3]u8 = .{ '1', '2', '3' };
    try send_sock.send(io, &recv_sock.address, &send_data);

    var recv_buf: [4]u8 = undefined;
    const received = try recv_sock.receive(io, &recv_buf);
    try testing.expect(received.from.eql(&send_sock.address));
    try testing.expectEqualStrings(&send_data, received.data);
}

test "UDP sendTimeout and receiveTimeout" {
    const io = testing.io;
    const localhost: net.IpAddress = .{ .ip4 = .loopback(0) };

    const recv_sock = localhost.bind(io, .{ .mode = .dgram }) catch |err| switch (err) {
        error.NetworkDown => return error.SkipZigTest,
        else => |e| return e,
    };
    defer recv_sock.close(io);
    const send_sock = try localhost.bind(io, .{ .mode = .dgram });
    defer send_sock.close(io);

    const six_hours: Io.Timeout = .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(21600) } };

    const send_data: [3]u8 = .{ '1', '2', '3' };
    send_sock.sendTimeout(io, &recv_sock.address, &send_data, six_hours) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
        else => |e| return e,
    };

    var recv_buf: [4]u8 = undefined;
    const received = try recv_sock.receiveTimeout(io, &recv_buf, six_hours);
    try testing.expect(received.from.eql(&send_sock.address));
    try testing.expectEqualStrings(&send_data, received.data);

    const short: Io.Timeout = .{ .duration = .{ .clock = .awake, .raw = .fromMicroseconds(123) } };
    try testing.expectError(error.Timeout, recv_sock.receiveTimeout(io, &recv_buf, short));
}

test "UDP sendMany 2 and receive 2" {
    const io = testing.io;
    const localhost: net.IpAddress = .{ .ip4 = .loopback(0) };

    const recv_sock = localhost.bind(io, .{ .mode = .dgram }) catch |err| switch (err) {
        error.NetworkDown => return error.SkipZigTest,
        else => |e| return e,
    };
    defer recv_sock.close(io);
    const send_sock = try localhost.bind(io, .{ .mode = .dgram });
    defer send_sock.close(io);

    const send_data: [3]u8 = .{ '1', '2', '3' };
    var send_msgs: [2]Io.net.OutgoingMessage = @splat(.{
        .address = &recv_sock.address,
        .data_ptr = &send_data,
        .data_len = 3,
    });
    // note sendMany is deprecated, but should remain tested until removed
    try send_sock.sendMany(io, &send_msgs, .{});
    try testing.expectEqual(3, send_msgs[0].data_len);
    try testing.expectEqual(3, send_msgs[1].data_len);

    var recv_buf: [4]u8 = undefined;

    {
        const first = try recv_sock.receive(io, &recv_buf);
        try testing.expect(first.from.eql(&send_sock.address));
        try testing.expectEqualStrings(&send_data, first.data);
    }

    {
        const second = try recv_sock.receive(io, &recv_buf);
        try testing.expect(second.from.eql(&send_sock.address));
        try testing.expectEqualStrings(&send_data, second.data);
    }
}

test "UDP sendManyTimeout 1 recvManyTimeout 2" {
    const io = testing.io;
    const localhost: net.IpAddress = .{ .ip4 = .loopback(0) };

    const recv_sock = localhost.bind(io, .{ .mode = .dgram }) catch |err| switch (err) {
        error.NetworkDown => return error.SkipZigTest,
        else => |e| return e,
    };
    defer recv_sock.close(io);
    const send_sock = try localhost.bind(io, .{ .mode = .dgram });
    defer send_sock.close(io);

    const six_hours: Io.Timeout = .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(21600) } };
    const send_data: [3]u8 = .{ '1', '2', '3' };
    var send_msg: Io.net.OutgoingMessage = .{
        .address = &recv_sock.address,
        .data_ptr = &send_data,
        .data_len = 3,
    };

    const maybe_send_err, const send_count = send_sock.sendManyTimeout(io, (&send_msg)[0..1], .{}, six_hours);
    if (maybe_send_err) |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
        else => |e| return e,
    };
    try testing.expectEqual(1, send_count);
    try testing.expectEqual(3, send_msg.data_len);

    // This should complete as soon as the first message arrives, and not stall
    // for the timeout waiting on the second one.
    var recv_msgs: [2]net.IncomingMessage = @splat(.init);
    var recv_buf: [10]u8 = undefined;
    const maybe_recv_err, const recv_count = recv_sock.receiveManyTimeout(io, &recv_msgs, &recv_buf, .{}, six_hours);
    if (maybe_recv_err) |err| return err;
    try testing.expectEqual(1, recv_count);
    try testing.expect(recv_msgs[0].from.eql(&send_sock.address));
    try testing.expectEqualStrings(&send_data, recv_msgs[0].data);
}

fn testUdpSender(io: Io, send_sock: Io.net.Socket, send_data: []const u8, dest: Io.net.IpAddress) !void {
    try io.sleep(.fromMilliseconds(10), .boot);
    try send_sock.send(io, &dest, send_data);
    try send_sock.send(io, &dest, send_data);
    try io.sleep(.fromMilliseconds(10), .boot);
    try send_sock.send(io, &dest, send_data);
}

test "UDP concurrency and timeouts" {
    const io = testing.io;
    const localhost: net.IpAddress = .{ .ip4 = .loopback(0) };

    const recv_sock = localhost.bind(io, .{ .mode = .dgram }) catch |err| switch (err) {
        error.NetworkDown => return error.SkipZigTest,
        else => |e| return e,
    };
    defer recv_sock.close(io);
    const send_sock = try localhost.bind(io, .{ .mode = .dgram });
    defer send_sock.close(io);

    const send_data: [3]u8 = .{ '1', '2', '3' };
    var sender = io.async(testUdpSender, .{ io, send_sock, &send_data, recv_sock.address });
    defer sender.cancel(io) catch {};

    // Because the sender is async (may execute serially or concurrently) and
    // it has some 10ms timing gaps, it's likely that there will be a variety
    // of random behaviors (total iterations, messages per iteration) on the
    // receive end of things related to the target and runner conditions. This
    // should still suceed so long as all 3 packets arrive in reasonable time.
    const six_hours: Io.Timeout = .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(21600) } };
    var received: usize = 0;
    for (0..3) |_| {
        var recv_msgs: [3]net.IncomingMessage = @splat(.init);
        var recv_buf: [9]u8 = undefined;
        const maybe_recv_err, const recv_count = recv_sock.receiveManyTimeout(io, &recv_msgs, &recv_buf, .{}, six_hours);
        if (maybe_recv_err) |err| switch (err) {
            error.ConcurrencyUnavailable => return error.SkipZigTest,
            else => |e| return e,
        };
        received += recv_count;
        try testing.expect(received <= 3);
        for (0..recv_count) |i| {
            const msg = recv_msgs[i];
            try testing.expect(msg.from.eql(&send_sock.address));
            try testing.expectEqualStrings(&send_data, msg.data);
        }
        if (received == 3) break;
    }
    try testing.expectEqual(3, received);
    try sender.await(io); // ensure sender didn't fail
}
