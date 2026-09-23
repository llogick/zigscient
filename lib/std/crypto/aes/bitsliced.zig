//! Bitsliced AES round function, for targets without hardware AES support.
//! It has no data-dependent memory access, so it is constant time.

const std = @import("../../std.zig");
const builtin = @import("builtin");
const mem = std.mem;

/// The widest batch of AES blocks the target supports
pub const Wide = if (builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64 or @bitSizeOf(usize) >= 64) Batch(2) else Batch(1);

/// Number of AES blocks we can process together
pub const width = Wide.nblocks;

/// A state holding a whole `width`-block batch
pub const State = Wide.Bitsliced;

/// A batch of `8 * lanes` blocks, one 32-bit lane per group of eight blocks
pub fn Batch(comptime lanes: usize) type {
    return struct {
        pub const Word = @Int(.unsigned, 32 * lanes);
        const Shift = std.math.Log2Int(Word);

        const nblocks = 8 * lanes;
        pub const Bitsliced = [32]Word;

        /// Splat a 32-bit pattern across all lanes of a word
        pub fn splatWord(x: u32) Word {
            const t: [lanes]u32 = @splat(x);
            return @bitCast(t);
        }

        fn laneRotl(x: Word, comptime n: u5) Word {
            if (lanes == 1) return std.math.rotl(u32, x, n);
            const lo_bits = (@as(u32, 1) << n) - 1;
            const mask_lo = comptime splatWord(lo_bits);
            const mask_hi = comptime splatWord(~lo_bits);
            const l: Shift = n;
            const r: Shift = @intCast(32 - @as(u32, n));
            return ((x << l) & mask_hi) | ((x >> r) & mask_lo);
        }

        pub fn swapMove(a: *Word, b: *Word, comptime mask32: u32, comptime n: comptime_int) void {
            const shift: Shift = n;
            const mask = comptime splatWord(mask32);
            const tmp = (b.* ^ (a.* >> shift)) & mask;
            b.* ^= tmp;
            a.* ^= tmp << shift;
        }

        fn sbox(u: []Word) void {
            const s0 = u[4] ^ u[16];
            const s1 = u[20] ^ u[28];
            const s2 = u[12] ^ s0;
            const s3 = u[0] ^ u[8];
            const q0 = s1 ^ s2;
            const s4 = u[0] ^ u[24];
            const s5 = u[8] ^ u[24];
            const s6 = u[12] ^ s1;
            const s7 = u[20] ^ s3;
            const q1 = s1 ^ s5;
            const q2 = u[8] ^ q0;
            const q3 = s4 ^ s2;
            const q4 = s3 ^ q0;
            const s8 = u[16] ^ s3;
            const q5 = s6 ^ s8;
            const q6 = u[8] ^ u[12];
            const q7 = u[24] ^ s2;
            const s9 = u[24] ^ s0;
            const q8 = s3 ^ s9;
            const q9 = s4 ^ s6;
            const q10 = s0 ^ s5;
            const q12 = u[28] ^ s2;
            const q13 = u[4] ^ s7;
            const q14 = u[28] ^ s3;
            const q15 = s2 ^ s7;
            const q16 = u[4] ^ s1;
            const q17 = u[4] ^ u[28];
            const q11 = u[20];

            const t20 = q6 & q12;
            const t21 = q3 & q14;
            const t22 = q1 & q16;
            const t23 = q2 & q17;
            const x0 = ((q3 | q14) ^ (q0 & q7)) ^ (t20 ^ t22);
            const x1 = ((q4 | q13) ^ (q10 & q11)) ^ (t21 ^ t20);
            const x2 = ((q2 | q17) ^ (q5 & q9)) ^ (t21 ^ t22);
            const x3 = ((q8 | q15) ^ t23) ^ (t21 ^ (q4 & q13));

            const a = x1 & ~x3;
            const b = x0 & ~x3;
            const c = x3 & ~x1;
            const d = x2 & ~x1;
            const e = x0 ^ a;
            const y0 = x3 ^ (x2 & ~e);
            const f = x1 ^ b;
            const y1 = c ^ (x2 & f);
            const g = x2 ^ c;
            const y2 = x1 ^ (x0 & ~g);
            const h = x3 ^ d;
            const y3 = a ^ (x0 & h);
            const y02 = y2 ^ y0;
            const y13 = y3 ^ y1;
            const y23 = y3 ^ y2;
            const y01 = y1 ^ y0;
            const y00 = y02 ^ y13;

            const a0 = y01 & q11;
            const a1 = y0 & q12;
            const a2 = y1 & q0;
            const a3 = y23 & q17;
            const a4 = y2 & q5;
            const a5 = y3 & q15;
            const a6 = y13 & q14;
            const a7 = y00 & q16;
            const a8 = y02 & q13;
            const a9 = y01 & q7;
            const a10 = y0 & q10;
            const a11 = y1 & q6;
            const a12 = y23 & q2;
            const a13 = y2 & q9;
            const a14 = y3 & q8;
            const a15 = y13 & q3;
            const a16 = y00 & q1;
            const a17 = y02 & q4;

            const r0 = a1 ^ a5;
            const r1 = a9 ^ a15;
            const r2 = a4 ^ r0;
            const r3 = a2 ^ a10;
            const r4 = a11 ^ a17;
            const r5 = a8 ^ r1;
            const r6 = a0 ^ a16;
            const r7 = a7 ^ a13;
            const r8 = a11 ^ a14;
            const r9 = r3 ^ r4;
            const r10 = r5 ^ r6;
            const r11 = r2 ^ r9;
            const r12 = a3 ^ r0;
            const r13 = r7 ^ r8;
            const r14 = r12 ^ r13;
            u[0] = r10 ^ r14;
            const r15 = a6 ^ a10;
            const r16 = r15 ^ r2;
            u[4] = ~(r10 ^ r16);
            u[8] = ~(a2 ^ r2);
            const r17 = a12 ^ a13;
            const r18 = a15 ^ r17;
            u[12] = r18 ^ r11;
            const r19 = a1 ^ a14;
            const r20 = a17 ^ r3;
            const r21 = r7 ^ r19;
            const r22 = r5 ^ r20;
            u[16] = r21 ^ r22;
            const r23 = a9 ^ a12;
            u[20] = r8 ^ r23;
            u[24] = ~(r1 ^ r4);
            u[28] = ~(a16 ^ r11);
        }

        fn subBytes(st: *Bitsliced) void {
            sbox(st[0..]);
            sbox(st[1..]);
            sbox(st[2..]);
            sbox(st[3..]);
        }

        fn shiftRows(st: *Bitsliced) void {
            var i: usize = 0;
            while (i < 32) : (i += 4) {
                st[i + 1] = laneRotl(st[i + 1], 24);
                st[i + 2] = laneRotl(st[i + 2], 16);
                st[i + 3] = laneRotl(st[i + 3], 8);
            }
        }

        fn mixColumns(st: *Bitsliced) void {
            const t2_0 = st[0] ^ st[1];
            const t2_1 = st[1] ^ st[2];
            const t2_2 = st[2] ^ st[3];
            const t2_3 = st[3] ^ st[0];
            var t0_0 = st[28] ^ st[29];
            var t0_1 = st[29] ^ st[30];
            var t0_2 = st[30] ^ st[31];
            var t0_3 = st[31] ^ st[28];
            var t = st[28];
            st[28] = t2_0 ^ t0_2 ^ st[29];
            st[29] = t2_1 ^ t0_2 ^ t;
            t = st[30];
            st[30] = t2_2 ^ t0_0 ^ st[31];
            st[31] = t2_3 ^ t0_0 ^ t;
            var t1_0 = st[24] ^ st[25];
            var t1_1 = st[25] ^ st[26];
            var t1_2 = st[26] ^ st[27];
            var t1_3 = st[27] ^ st[24];
            t = st[24];
            st[24] = t0_0 ^ t2_0 ^ st[25] ^ t1_2;
            var t_bis = st[25];
            st[25] = t0_1 ^ t2_1 ^ t1_2 ^ t;
            t = st[26];
            st[26] = t0_2 ^ t2_2 ^ t1_3 ^ t_bis;
            st[27] = t0_3 ^ t2_3 ^ t1_0 ^ t;
            t0_0 = st[20] ^ st[21];
            t0_1 = st[21] ^ st[22];
            t0_2 = st[22] ^ st[23];
            t0_3 = st[23] ^ st[20];
            t = st[20];
            st[20] = t1_0 ^ t0_1 ^ st[23];
            t_bis = st[21];
            st[21] = t1_1 ^ t0_2 ^ t;
            t = st[22];
            st[22] = t1_2 ^ t0_3 ^ t_bis;
            st[23] = t1_3 ^ t0_0 ^ t;
            t1_0 = st[16] ^ st[17];
            t1_1 = st[17] ^ st[18];
            t1_2 = st[18] ^ st[19];
            t1_3 = st[19] ^ st[16];
            t = st[16];
            st[16] = t0_0 ^ t2_0 ^ t1_1 ^ st[19];
            t_bis = st[17];
            st[17] = t0_1 ^ t2_1 ^ t1_2 ^ t;
            t = st[18];
            st[18] = t0_2 ^ t2_2 ^ t1_3 ^ t_bis;
            st[19] = t0_3 ^ t2_3 ^ t1_0 ^ t;
            t0_0 = st[12] ^ st[13];
            t0_1 = st[13] ^ st[14];
            t0_2 = st[14] ^ st[15];
            t0_3 = st[15] ^ st[12];
            t = st[12];
            st[12] = t1_0 ^ t2_0 ^ t0_1 ^ st[15];
            t_bis = st[13];
            st[13] = t1_1 ^ t2_1 ^ t0_2 ^ t;
            t = st[14];
            st[14] = t1_2 ^ t2_2 ^ t0_3 ^ t_bis;
            st[15] = t1_3 ^ t2_3 ^ t0_0 ^ t;
            t1_0 = st[8] ^ st[9];
            t1_1 = st[9] ^ st[10];
            t1_2 = st[10] ^ st[11];
            t1_3 = st[11] ^ st[8];
            t = st[8];
            st[8] = t0_0 ^ t1_1 ^ st[11];
            t_bis = st[9];
            st[9] = t0_1 ^ t1_2 ^ t;
            t = st[10];
            st[10] = t0_2 ^ t1_3 ^ t_bis;
            st[11] = t0_3 ^ t1_0 ^ t;
            t0_0 = st[4] ^ st[5];
            t0_1 = st[5] ^ st[6];
            t0_2 = st[6] ^ st[7];
            t0_3 = st[7] ^ st[4];
            t = st[4];
            st[4] = t1_0 ^ t0_1 ^ st[7];
            t_bis = st[5];
            st[5] = t1_1 ^ t0_2 ^ t;
            t = st[6];
            st[6] = t1_2 ^ t0_3 ^ t_bis;
            st[7] = t1_3 ^ t0_0 ^ t;
            t = st[0];
            st[0] = t0_0 ^ t2_1 ^ st[3];
            t_bis = st[1];
            st[1] = t0_1 ^ t2_2 ^ t;
            t = st[2];
            st[2] = t0_2 ^ t2_3 ^ t_bis;
            st[3] = t0_3 ^ t2_0 ^ t;
        }

        /// One keyless AES round (SubBytes, ShiftRows, MixColumns) over the whole batch
        pub fn round(st: *Bitsliced) void {
            subBytes(st);
            shiftRows(st);
            mixColumns(st);
        }

        /// Add a round key, which must also be in bitsliced form
        pub fn addRoundKey(st: *Bitsliced, round_key: *const Bitsliced) void {
            for (0..32) |i| st[i] ^= round_key[i];
        }

        /// Orthogonalization (converts blocks-in-words to bit slices)
        pub fn packState(st: *Bitsliced) void {
            var i: usize = 0;
            while (i < 32) : (i += 4) {
                swapMove(&st[i], &st[i + 1], 0x00ff00ff, 8);
                swapMove(&st[i + 2], &st[i + 3], 0x00ff00ff, 8);
                swapMove(&st[i], &st[i + 2], 0x0000ffff, 16);
                swapMove(&st[i + 1], &st[i + 3], 0x0000ffff, 16);
            }
            for (0..4) |k| {
                swapMove(&st[k + 4], &st[k], 0x55555555, 1);
                swapMove(&st[k + 12], &st[k + 8], 0x55555555, 1);
                swapMove(&st[k + 20], &st[k + 16], 0x55555555, 1);
                swapMove(&st[k + 28], &st[k + 24], 0x55555555, 1);
                swapMove(&st[k + 8], &st[k], 0x33333333, 2);
                swapMove(&st[k + 12], &st[k + 4], 0x33333333, 2);
                swapMove(&st[k + 24], &st[k + 16], 0x33333333, 2);
                swapMove(&st[k + 28], &st[k + 20], 0x33333333, 2);
                swapMove(&st[k + 16], &st[k], 0x0f0f0f0f, 4);
                swapMove(&st[k + 20], &st[k + 4], 0x0f0f0f0f, 4);
                swapMove(&st[k + 24], &st[k + 8], 0x0f0f0f0f, 4);
                swapMove(&st[k + 28], &st[k + 12], 0x0f0f0f0f, 4);
            }
        }

        /// Inverse of `packState`
        pub fn unpackState(st: *Bitsliced) void {
            for (0..4) |k| {
                swapMove(&st[k + 4], &st[k], 0x55555555, 1);
                swapMove(&st[k + 12], &st[k + 8], 0x55555555, 1);
                swapMove(&st[k + 20], &st[k + 16], 0x55555555, 1);
                swapMove(&st[k + 28], &st[k + 24], 0x55555555, 1);
                swapMove(&st[k + 8], &st[k], 0x33333333, 2);
                swapMove(&st[k + 12], &st[k + 4], 0x33333333, 2);
                swapMove(&st[k + 24], &st[k + 16], 0x33333333, 2);
                swapMove(&st[k + 28], &st[k + 20], 0x33333333, 2);
                swapMove(&st[k + 16], &st[k], 0x0f0f0f0f, 4);
                swapMove(&st[k + 20], &st[k + 4], 0x0f0f0f0f, 4);
                swapMove(&st[k + 24], &st[k + 8], 0x0f0f0f0f, 4);
                swapMove(&st[k + 28], &st[k + 12], 0x0f0f0f0f, 4);
            }
            var i: usize = 0;
            while (i < 32) : (i += 4) {
                swapMove(&st[i], &st[i + 2], 0x0000ffff, 16);
                swapMove(&st[i + 1], &st[i + 3], 0x0000ffff, 16);
                swapMove(&st[i], &st[i + 1], 0x00ff00ff, 8);
                swapMove(&st[i + 2], &st[i + 3], 0x00ff00ff, 8);
            }
        }

        /// Convert `nblocks` little-endian blocks into the packed state.
        /// Blocks`8*g .. 8*g+7` land in lane `g` of each word.
        fn pack(bytes: *const [nblocks * 16]u8) Bitsliced {
            var st: Bitsliced = @splat(0);
            inline for (0..nblocks) |bl| {
                const g = bl / 8;
                const p = bl % 8;
                inline for (0..4) |wd| {
                    const v = mem.readInt(u32, bytes[bl * 16 + wd * 4 ..][0..4], .little);
                    st[p * 4 + wd] |= @as(Word, v) << (32 * g);
                }
            }
            packState(&st);
            return st;
        }

        /// Inverse of `pack`
        fn unpack(st: *Bitsliced) [nblocks * 16]u8 {
            unpackState(st);
            var bytes: [nblocks * 16]u8 = undefined;
            inline for (0..nblocks) |bl| {
                const g = bl / 8;
                const p = bl % 8;
                inline for (0..4) |wd| {
                    const v: u32 = @truncate(st[p * 4 + wd] >> (32 * g));
                    mem.writeInt(u32, bytes[bl * 16 + wd * 4 ..][0..4], v, .little);
                }
            }
            return bytes;
        }

        /// Precompute where key bit `i` of a round key lands after packing
        const broadcast_loc = blk: {
            @setEvalBranchQuota(200000);
            var loc: [128]struct { word: u8, shift: u5 } = undefined;
            for (0..128) |i| {
                var st: Bitsliced = @splat(0);
                const word = (i / 8) / 4;
                const bit: u5 = @intCast(((i / 8) % 4) * 8 + (i % 8));
                for (0..8) |b| st[b * 4 + word] |= @as(Word, 1) << bit;
                packState(&st);
                found: for (0..32) |w| {
                    for (0..4) |byte| {
                        if ((st[w] >> @intCast(byte * 8)) & 0xff == 0xff) {
                            loc[i] = .{ .word = @intCast(w), .shift = @intCast(byte * 8) };
                            break :found;
                        }
                    }
                }
            }
            break :blk loc;
        };

        /// Pack a round key and broadcast it to all blocks, so it can be directly XORed into a packed state
        fn packRoundKey(round_key: *const [16]u8) Bitsliced {
            var st: Bitsliced = @splat(0);
            inline for (0..16) |pos| {
                const byte = round_key[pos];
                inline for (0..8) |bit| {
                    const smear: Word = 0 -% @as(Word, (byte >> bit) & 1);
                    const loc = broadcast_loc[pos * 8 + bit];
                    st[loc.word] |= smear & (splatWord(0xff) << loc.shift);
                }
            }
            return st;
        }

        /// Pack a whole key schedule into the bitsliced representation.
        pub fn packKeys(round_keys: anytype) [round_keys.len]Bitsliced {
            var keys: [round_keys.len]Bitsliced = undefined;
            inline for (&keys, 0..) |*k, r| {
                const bytes = round_keys[r].toBytes();
                k.* = packRoundKey(&bytes);
            }
            return keys;
        }

        /// Run the full AES cipher over the whole batch in place
        pub fn encrypt(comptime rounds: usize, keys: *const [rounds + 1]Bitsliced, data: *[nblocks * 16]u8) void {
            var st = pack(data);
            addRoundKey(&st, &keys[0]);
            inline for (1..rounds) |r| {
                round(&st);
                addRoundKey(&st, &keys[r]);
            }
            subBytes(&st);
            shiftRows(&st);
            addRoundKey(&st, &keys[rounds]);
            data.* = unpack(&st);
        }

        fn invShiftRows(st: *Bitsliced) void {
            var i: usize = 0;
            while (i < 32) : (i += 4) {
                st[i + 1] = laneRotl(st[i + 1], 8);
                st[i + 2] = laneRotl(st[i + 2], 16);
                st[i + 3] = laneRotl(st[i + 3], 24);
            }
        }

        /// Precompute the `mixColumns` inverse matrix
        const mix_inv: [32]u32 = blk: {
            @setEvalBranchQuota(200000);
            var m: [32]u32 = @splat(0);
            for (0..32) |i| {
                var st: Bitsliced = @splat(0);
                st[i] = 1;
                mixColumns(&st);
                for (0..32) |o| {
                    if (st[o] & 1 == 1) m[o] |= @as(u32, 1) << @intCast(i);
                }
            }
            var inv: [32]u32 = undefined;
            for (0..32) |k| inv[k] = @as(u32, 1) << @intCast(k);
            for (0..32) |col| {
                var piv = col;
                while (m[piv] & (@as(u32, 1) << @intCast(col)) == 0) piv += 1;
                const tm = m[col];
                m[col] = m[piv];
                m[piv] = tm;
                const ti = inv[col];
                inv[col] = inv[piv];
                inv[piv] = ti;
                for (0..32) |r| {
                    if (r != col and (m[r] & (@as(u32, 1) << @intCast(col))) != 0) {
                        m[r] ^= m[col];
                        inv[r] ^= inv[col];
                    }
                }
            }
            break :blk inv;
        };

        fn invMixColumns(st: *Bitsliced) void {
            @setEvalBranchQuota(20000);
            var out: Bitsliced = @splat(0);
            inline for (0..32) |o| {
                inline for (0..32) |j| {
                    if (mix_inv[o] & (@as(u32, 1) << @intCast(j)) != 0) out[o] ^= st[j];
                }
            }
            st.* = out;
        }

        /// Linear map for the inverse S-box
        fn invAffineGroup(st: *Bitsliced, comptime g: usize) void {
            const p = [8]usize{ g + 28, g + 24, g + 20, g + 16, g + 12, g + 8, g + 4, g };
            const a0 = ~st[p[0]];
            const a1 = ~st[p[1]];
            const a2 = st[p[2]];
            const a3 = st[p[3]];
            const a4 = st[p[4]];
            const a5 = ~st[p[5]];
            const a6 = ~st[p[6]];
            const a7 = st[p[7]];
            st[p[7]] = a1 ^ a4 ^ a6;
            st[p[6]] = a0 ^ a3 ^ a5;
            st[p[5]] = a7 ^ a2 ^ a4;
            st[p[4]] = a6 ^ a1 ^ a3;
            st[p[3]] = a5 ^ a0 ^ a2;
            st[p[2]] = a4 ^ a7 ^ a1;
            st[p[1]] = a3 ^ a6 ^ a0;
            st[p[0]] = a2 ^ a5 ^ a7;
        }

        /// Compact inverse S-box: we apply a fixed linear map, the forward S-box, then the same linear map
        /// Trick from Thomas Pornin
        fn invSubBytes(st: *Bitsliced) void {
            inline for (0..4) |g| invAffineGroup(st, g);
            subBytes(st);
            inline for (0..4) |g| invAffineGroup(st, g);
        }

        /// Full inverse AES cipher over the whole batch in bitsliced representation
        pub fn decrypt(comptime rounds: usize, keys: *const [rounds + 1]Bitsliced, data: *[nblocks * 16]u8) void {
            var st = pack(data);
            addRoundKey(&st, &keys[rounds]);
            comptime var r: usize = rounds - 1;
            inline while (r > 0) : (r -= 1) {
                invShiftRows(&st);
                invSubBytes(&st);
                addRoundKey(&st, &keys[r]);
                invMixColumns(&st);
            }
            invShiftRows(&st);
            invSubBytes(&st);
            addRoundKey(&st, &keys[0]);
            data.* = unpack(&st);
        }
    };
}

const testing = std.testing;

test "bitslice cross-check against table AES" {
    const key: [16]u8 = @splat(0x37);
    const ref = std.crypto.core.aes.Aes128.initEnc(key);
    const keys = Wide.packKeys(ref.key_schedule.round_keys[0..]);

    var data: [width * 16]u8 = undefined;
    for (0..width * 16) |i| data[i] = @truncate(i *% 101 +% 7);

    var expected: [width * 16]u8 = undefined;
    for (0..width) |b| {
        var blk: [16]u8 = data[b * 16 ..][0..16].*;
        ref.encrypt(&blk, &blk);
        expected[b * 16 ..][0..16].* = blk;
    }

    Wide.encrypt(10, &keys, &data);
    try testing.expectEqualSlices(u8, &expected, &data);
}

test "bitslice decrypt cross-check against table AES" {
    inline for (.{ std.crypto.core.aes.Aes128, std.crypto.core.aes.Aes256 }) |Aes| {
        const key: [Aes.key_bits / 8]u8 = @splat(0x4d);
        const enc = Aes.initEnc(key);
        const dec = Aes.initDec(key);
        const keys = Wide.packKeys(enc.key_schedule.round_keys[0..]);

        var data: [width * 16]u8 = undefined;
        for (0..width * 16) |i| data[i] = @truncate(i *% 211 +% 13);

        var expected: [width * 16]u8 = undefined;
        for (0..width) |b| {
            var blk: [16]u8 = data[b * 16 ..][0..16].*;
            dec.decrypt(&blk, &blk);
            expected[b * 16 ..][0..16].* = blk;
        }

        Wide.decrypt(Aes.rounds, &keys, &data);
        try testing.expectEqualSlices(u8, &expected, &data);
    }
}
