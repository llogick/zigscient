//! Constant-time AEGIS states for targets without AES instructions.
//!
//! We keep the AEGIS state in bitsliced form as much as possible.

const std = @import("../../std.zig");
const mem = std.mem;
const bitsliced_aes = @import("../aes/bitsliced.zig");

const c1_bytes = [16]u8{ 0xdb, 0x3d, 0x18, 0x55, 0x6d, 0xc2, 0x2f, 0xf1, 0x20, 0x11, 0x31, 0x42, 0x73, 0xb5, 0x28, 0xdd };
const c2_bytes = [16]u8{ 0x0, 0x1, 0x01, 0x02, 0x03, 0x05, 0x08, 0x0d, 0x15, 0x22, 0x37, 0x59, 0x90, 0xe9, 0x79, 0x62 };

fn Lanes(comptime degree: u7) type {
    return struct {
        const Aes = bitsliced_aes.Batch(degree);
        const Word = Aes.Word;
        const block_length = @as(usize, degree) * 16;

        fn mask(comptime b: u8) Word {
            return comptime Aes.splatWord(@as(u32, 0x01010101) * b);
        }

        fn loadBlock(bytes: *const [block_length]u8) [4]Word {
            var w: [4]Word = @splat(0);
            inline for (0..degree) |g| {
                inline for (0..4) |wd| {
                    const v = mem.readInt(u32, bytes[g * 16 + wd * 4 ..][0..4], .little);
                    w[wd] |= @as(Word, v) << (32 * g);
                }
            }
            return w;
        }

        fn storeBlock(bytes: *[block_length]u8, w: [4]Word) void {
            inline for (0..degree) |g| {
                inline for (0..4) |wd| {
                    const v: u32 = @truncate(w[wd] >> (32 * g));
                    mem.writeInt(u32, bytes[g * 16 + wd * 4 ..][0..4], v, .little);
                }
            }
        }

        fn broadcastBlock(bytes: *const [16]u8) [4]Word {
            var w: [4]Word = undefined;
            inline for (&w, 0..) |*x, wd| {
                x.* = Aes.splatWord(mem.readInt(u32, bytes[wd * 4 ..][0..4], .little));
            }
            return w;
        }

        /// Returns two little-endian 64-bit lengths in every lane.
        fn sizesBlock(a: u64, b: u64) [4]Word {
            return .{
                Aes.splatWord(@truncate(a)),
                Aes.splatWord(@truncate(a >> 32)),
                Aes.splatWord(@truncate(b)),
                Aes.splatWord(@truncate(b >> 32)),
            };
        }

        fn xorBlocks(a: [4]Word, b: [4]Word) [4]Word {
            var w: [4]Word = undefined;
            inline for (&w, a, b) |*x, y, z| x.* = y ^ z;
            return w;
        }

        fn contextMask(comptime slots: [2]usize) Aes.Bitsliced {
            @setEvalBranchQuota(50000);
            var ctx: [4]Word = @splat(0);
            for (0..degree) |g| ctx[0] |= ((@as(Word, degree) - 1) * 256 + g) << (32 * g);
            return packBlocks(&slots, .{ ctx, ctx });
        }

        const Swap = struct { usize, usize, u32, comptime_int };

        /// Swaps, in execution order.
        const pack_swaps = swaps: {
            var swaps: []const Swap = &.{};
            for (0..8) |g| {
                const i = g * 4;
                swaps = swaps ++ [_]Swap{
                    .{ i, i + 1, 0x00ff00ff, 8 },
                    .{ i + 2, i + 3, 0x00ff00ff, 8 },
                    .{ i, i + 2, 0x0000ffff, 16 },
                    .{ i + 1, i + 3, 0x0000ffff, 16 },
                };
            }
            for (0..4) |k| {
                swaps = swaps ++ [_]Swap{
                    .{ k + 4, k, 0x55555555, 1 },
                    .{ k + 12, k + 8, 0x55555555, 1 },
                    .{ k + 20, k + 16, 0x55555555, 1 },
                    .{ k + 28, k + 24, 0x55555555, 1 },
                    .{ k + 8, k, 0x33333333, 2 },
                    .{ k + 12, k + 4, 0x33333333, 2 },
                    .{ k + 24, k + 16, 0x33333333, 2 },
                    .{ k + 28, k + 20, 0x33333333, 2 },
                    .{ k + 16, k, 0x0f0f0f0f, 4 },
                    .{ k + 20, k + 4, 0x0f0f0f0f, 4 },
                    .{ k + 24, k + 8, 0x0f0f0f0f, 4 },
                    .{ k + 28, k + 12, 0x0f0f0f0f, 4 },
                };
            }
            break :swaps swaps;
        };

        /// Returns the swaps needed when only `slots` contain input blocks.
        fn nonzeroSwaps(comptime slots: []const usize) []const Swap {
            var nonzero: [32]bool = @splat(false);
            for (slots) |p| nonzero[p * 4 ..][0..4].* = @splat(true);
            var swaps: []const Swap = &.{};
            for (pack_swaps) |s| {
                if (!nonzero[s[0]] and !nonzero[s[1]]) continue;
                nonzero[s[0]] = true;
                nonzero[s[1]] = true;
                swaps = swaps ++ [_]Swap{s};
            }
            return swaps;
        }

        /// Packs blocks in `slots`, skipping unnecessary swaps.
        fn packBlocks(comptime slots: []const usize, blocks: [slots.len][4]Word) Aes.Bitsliced {
            var st: Aes.Bitsliced = @splat(0);
            inline for (slots, blocks) |p, b| st[p * 4 ..][0..4].* = b;
            inline for (comptime nonzeroSwaps(slots)) |s| Aes.swapMove(&st[s[0]], &st[s[1]], s[2], s[3]);
            return st;
        }

        fn unpackBlocks(st: Aes.Bitsliced, comptime slots: []const usize) [slots.len][4]Word {
            const swaps = comptime nonzeroSwaps(slots);
            var u = st;
            inline for (0..swaps.len) |i| {
                const s = swaps[swaps.len - 1 - i];
                Aes.swapMove(&u[s[0]], &u[s[1]], s[2], s[3]);
            }
            var blocks: [slots.len][4]Word = undefined;
            inline for (&blocks, slots) |*b, p| b.* = u[p * 4 ..][0..4].*;
            return blocks;
        }

        fn unpacked(words: Aes.Bitsliced) Aes.Bitsliced {
            var u = words;
            Aes.unpackState(&u);
            return u;
        }

        /// Combines each range of state blocks into a unique tag.
        fn laneTags(words: Aes.Bitsliced, comptime ranges: []const [2]usize) [ranges.len][block_length]u8 {
            const u = unpacked(words);
            var tags: [ranges.len][block_length]u8 = undefined;
            inline for (ranges, &tags) |r, *t| {
                var acc: [4]Word = @splat(0);
                inline for (r[0]..r[1]) |p| acc = xorBlocks(acc, u[p * 4 ..][0..4].*);
                storeBlock(t, acc);
            }
            return tags;
        }

        /// XORs all lane tags when `fold_lanes` is true; otherwise we return lane 0's tag.
        fn tag(words: Aes.Bitsliced, comptime ranges: []const [2]usize, comptime fold_lanes: bool) [ranges.len * 16]u8 {
            var out: [ranges.len * 16]u8 = undefined;
            for (laneTags(words, ranges), 0..) |t, i| {
                const lanes: [degree]@Vector(16, u8) = @bitCast(t);
                var folded = lanes[0];
                if (fold_lanes) {
                    for (lanes[1..]) |lane| folded ^= lane;
                }
                out[i * 16 ..][0..16].* = folded;
            }
            return out;
        }
    };
}

pub fn State128X(comptime degree: u7) type {
    return struct {
        const State = @This();
        const V = Lanes(degree);
        const Aes = V.Aes;
        const Word = V.Word;

        /// bit 7 - i of each byte belongs to state block i.
        words: Aes.Bitsliced,

        const aes_block_length = V.block_length;
        pub const rate = aes_block_length * 2;
        pub const alignment = @alignOf(Word);

        const context_mask = V.contextMask(.{ 3, 7 });

        pub fn init(key: [16]u8, nonce: [16]u8) State {
            const c1 = V.broadcastBlock(&c1_bytes);
            const c2 = V.broadcastBlock(&c2_bytes);
            const key_block = V.broadcastBlock(&key);
            const nonce_block = V.broadcastBlock(&nonce);
            const kxn = V.xorBlocks(key_block, nonce_block);
            var state = State{ .words = V.packBlocks(&.{ 0, 1, 2, 3, 4, 5, 6, 7 }, .{
                kxn,
                c1,
                c2,
                c1,
                kxn,
                V.xorBlocks(key_block, c2),
                V.xorBlocks(key_block, c1),
                V.xorBlocks(key_block, c2),
            }) };
            const input = packRate(nonce_block, key_block);
            for (0..10) |_| {
                inline for (&state.words, context_mask) |*w, m| w.* ^= m;
                state.update(&input);
            }
            return state;
        }

        fn update(state: *State, input: *const Aes.Bitsliced) void {
            var st1 = state.words;
            Aes.round(&st1);
            inline for (&state.words, st1, input) |*w, r, in| {
                w.* ^= (((r & V.mask(0xfe)) >> 1) | ((r & V.mask(0x01)) << 7)) ^ in;
            }
        }

        fn packRate(m0: [4]Word, m1: [4]Word) Aes.Bitsliced {
            return V.packBlocks(&.{ 0, 4 }, .{ m0, m1 });
        }

        fn keystream(state: *const State) [2][4]Word {
            var z: Aes.Bitsliced = undefined;
            inline for (&z, &state.words) |*zw, x| {
                zw.* = ((x & V.mask(0x02)) << 6) ^ ((x & V.mask(0x40)) << 1) ^
                    (((x & V.mask(0x20)) << 2) & ((x & V.mask(0x10)) << 3)) ^
                    ((x & V.mask(0x20)) >> 2) ^ ((x & V.mask(0x04)) << 1) ^
                    (((x & V.mask(0x02)) << 2) & ((x & V.mask(0x01)) << 3));
            }
            return V.unpackBlocks(z, &.{ 0, 4 });
        }

        pub fn absorb(state: *State, src: *const [rate]u8) void {
            const input = packRate(V.loadBlock(src[0..aes_block_length]), V.loadBlock(src[aes_block_length..rate]));
            state.update(&input);
        }

        pub fn enc(state: *State, dst: *[rate]u8, src: *const [rate]u8) void {
            const z = state.keystream();
            const m0 = V.loadBlock(src[0..aes_block_length]);
            const m1 = V.loadBlock(src[aes_block_length..rate]);
            const input = packRate(m0, m1);
            state.update(&input);
            V.storeBlock(dst[0..aes_block_length], V.xorBlocks(m0, z[0]));
            V.storeBlock(dst[aes_block_length..rate], V.xorBlocks(m1, z[1]));
        }

        pub fn dec(state: *State, dst: *[rate]u8, src: *const [rate]u8) void {
            const z = state.keystream();
            const m0 = V.xorBlocks(V.loadBlock(src[0..aes_block_length]), z[0]);
            const m1 = V.xorBlocks(V.loadBlock(src[aes_block_length..rate]), z[1]);
            const input = packRate(m0, m1);
            state.update(&input);
            V.storeBlock(dst[0..aes_block_length], m0);
            V.storeBlock(dst[aes_block_length..rate], m1);
        }

        pub fn decLast(state: *State, dst: []u8, src: []const u8) void {
            const z = state.keystream();
            var pad: [rate]u8 = undefined;
            V.storeBlock(pad[0..aes_block_length], z[0]);
            V.storeBlock(pad[aes_block_length..rate], z[1]);
            for (pad[0..src.len], src) |*p, x| p.* ^= x;
            @memcpy(dst, pad[0..src.len]);
            @memset(pad[src.len..], 0);
            state.absorb(&pad);
        }

        fn finalizeRounds(state: *State, sizes: [4]Word) void {
            const t = V.xorBlocks(sizes, V.unpacked(state.words)[8..12].*);
            const input = packRate(t, t);
            for (0..7) |_| state.update(&input);
        }

        fn tagRanges(comptime tag_bits: u9) []const [2]usize {
            return switch (tag_bits) {
                128 => &.{.{ 0, 7 }},
                256 => &.{ .{ 0, 4 }, .{ 4, 8 } },
                else => unreachable,
            };
        }

        pub fn finalize(state: *State, comptime tag_bits: u9, adlen: usize, mlen: usize) [tag_bits / 8]u8 {
            state.finalizeRounds(V.sizesBlock(@as(u64, adlen) * 8, @as(u64, mlen) * 8));
            return V.tag(state.words, tagRanges(tag_bits), true);
        }

        pub fn finalizeMac(state: *State, comptime tag_bits: u9, datalen: usize) [tag_bits / 8]u8 {
            state.finalizeRounds(V.sizesBlock(@as(u64, datalen) * 8, tag_bits));
            if (degree > 1) {
                const tags = V.laneTags(state.words, tagRanges(tag_bits));
                var v: [rate]u8 = @splat(0);
                switch (tag_bits) {
                    128 => for (0..degree / 2) |d| {
                        v[0..16].* = tags[0][d * 32 ..][0..16].*;
                        v[rate / 2 ..][0..16].* = tags[0][d * 32 ..][16..32].*;
                        state.absorb(&v);
                    },
                    256 => for (1..degree) |d| {
                        v[0..16].* = tags[0][d * 16 ..][0..16].*;
                        v[rate / 2 ..][0..16].* = tags[1][d * 16 ..][0..16].*;
                        state.absorb(&v);
                    },
                    else => unreachable,
                }
                state.finalizeRounds(V.sizesBlock(degree, tag_bits));
            }
            return V.tag(state.words, tagRanges(tag_bits), false);
        }
    };
}

pub fn State256X(comptime degree: u7) type {
    return struct {
        const State = @This();
        const V = Lanes(degree);
        const Aes = V.Aes;
        const Word = V.Word;

        /// bit 7 - i of each byte belongs to state block i.
        words: Aes.Bitsliced,

        pub const rate = V.block_length;
        pub const alignment = @alignOf(Word);

        const context_mask = V.contextMask(.{ 3, 5 });

        pub fn init(key: [32]u8, nonce: [32]u8) State {
            const c1 = V.broadcastBlock(&c1_bytes);
            const c2 = V.broadcastBlock(&c2_bytes);
            const key_block1 = V.broadcastBlock(key[0..16]);
            const key_block2 = V.broadcastBlock(key[16..32]);
            const nonce_block1 = V.broadcastBlock(nonce[0..16]);
            const nonce_block2 = V.broadcastBlock(nonce[16..32]);
            const kxn1 = V.xorBlocks(key_block1, nonce_block1);
            const kxn2 = V.xorBlocks(key_block2, nonce_block2);
            var state = State{ .words = V.packBlocks(&.{ 0, 1, 2, 3, 4, 5 }, .{
                kxn1,
                kxn2,
                c1,
                c2,
                V.xorBlocks(key_block1, c2),
                V.xorBlocks(key_block2, c1),
            }) };
            const inputs = [4]Aes.Bitsliced{
                packRate(key_block1),
                packRate(key_block2),
                packRate(kxn1),
                packRate(kxn2),
            };
            for (0..4) |_| {
                for (&inputs) |*input| {
                    inline for (&state.words, context_mask) |*w, m| w.* ^= m;
                    state.update(input);
                }
            }
            return state;
        }

        fn update(state: *State, input: *const Aes.Bitsliced) void {
            var st1 = state.words;
            Aes.round(&st1);
            inline for (&state.words, st1, input) |*w, r, in| {
                w.* ^= (((r & V.mask(0xf8)) >> 1) | ((r & V.mask(0x04)) << 5)) ^ in;
            }
        }

        fn packRate(m: [4]Word) Aes.Bitsliced {
            return V.packBlocks(&.{0}, .{m});
        }

        fn keystream(state: *const State) [4]Word {
            var z: Aes.Bitsliced = undefined;
            inline for (&z, &state.words) |*zw, x| {
                zw.* = ((x & V.mask(0x40)) << 1) ^ ((x & V.mask(0x08)) << 4) ^
                    ((x & V.mask(0x04)) << 5) ^
                    (((x & V.mask(0x20)) << 2) & ((x & V.mask(0x10)) << 3));
            }
            return V.unpackBlocks(z, &.{0})[0];
        }

        pub fn absorb(state: *State, src: *const [rate]u8) void {
            const input = packRate(V.loadBlock(src));
            state.update(&input);
        }

        pub fn enc(state: *State, dst: *[rate]u8, src: *const [rate]u8) void {
            const z = state.keystream();
            const m = V.loadBlock(src);
            const input = packRate(m);
            state.update(&input);
            V.storeBlock(dst, V.xorBlocks(m, z));
        }

        pub fn dec(state: *State, dst: *[rate]u8, src: *const [rate]u8) void {
            const z = state.keystream();
            const m = V.xorBlocks(V.loadBlock(src), z);
            const input = packRate(m);
            state.update(&input);
            V.storeBlock(dst, m);
        }

        pub fn decLast(state: *State, dst: []u8, src: []const u8) void {
            var pad: [rate]u8 = undefined;
            V.storeBlock(&pad, state.keystream());
            for (pad[0..src.len], src) |*p, x| p.* ^= x;
            @memcpy(dst, pad[0..src.len]);
            @memset(pad[src.len..], 0);
            state.absorb(&pad);
        }

        fn finalizeRounds(state: *State, sizes: [4]Word) void {
            const t = V.xorBlocks(sizes, V.unpacked(state.words)[12..16].*);
            const input = packRate(t);
            for (0..7) |_| state.update(&input);
        }

        fn tagRanges(comptime tag_bits: u9) []const [2]usize {
            return switch (tag_bits) {
                128 => &.{.{ 0, 6 }},
                256 => &.{ .{ 0, 3 }, .{ 3, 6 } },
                else => unreachable,
            };
        }

        pub fn finalize(state: *State, comptime tag_bits: u9, adlen: usize, mlen: usize) [tag_bits / 8]u8 {
            state.finalizeRounds(V.sizesBlock(@as(u64, adlen) * 8, @as(u64, mlen) * 8));
            return V.tag(state.words, tagRanges(tag_bits), true);
        }

        pub fn finalizeMac(state: *State, comptime tag_bits: u9, datalen: usize) [tag_bits / 8]u8 {
            state.finalizeRounds(V.sizesBlock(@as(u64, datalen) * 8, tag_bits));
            if (degree > 1) {
                const tags = V.laneTags(state.words, tagRanges(tag_bits));
                var v: [rate]u8 = @splat(0);
                for (1..degree) |d| {
                    for (tags) |t| {
                        v[0..16].* = t[d * 16 ..][0..16].*;
                        state.absorb(&v);
                    }
                }
                state.finalizeRounds(V.sizesBlock(degree, tag_bits));
            }
            return V.tag(state.words, tagRanges(tag_bits), false);
        }
    };
}
