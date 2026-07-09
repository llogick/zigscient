const std = @import("std");

/// Calculation operands:
///
/// * `A`: relocation addend
/// * `G`: symbol GOT slot offset
/// * `GOT`: GOT base address (`_GLOBAL_OFFSET_TABLE_` value)
/// * `L`: symbol PLT slot address
/// * `O`: secondary relocation addend
/// * `P`: relocation address
/// * `S`: symbol value
/// * `Z`: symbol size
///
/// Field semantics:
///
/// * `T-*`: truncate (don't check for overflow)
/// * `V-*`: verify (check for overflow)
pub const reloc = struct {
    /// R_SPARC_8                (V-byte8)     = S + A
    /// R_SPARC_DISP8            (V-byte8)     = S + A - P
    pub const Byte8 = packed struct(u8) {
        byte8: u8,
    };

    /// R_SPARC_16               (V-half16)    = S + A
    /// R_SPARC_DISP16           (V-half16)    = S + A - P
    /// R_SPARC_UA16             (V-half16)    = S + A
    pub const Half16 = packed struct(u16) {
        half16: u16,
    };

    /// R_SPARC_32               (V-word32)    = S + A
    /// R_SPARC_GLOB_DAT         (V-word32)    = S + A [32-bit only]
    /// R_SPARC_UA32             (V-word32)    = S + A
    /// R_SPARC_PCPLT32          (V-word32)    = L + A - P
    /// R_SPARC_REGISTER         (V-word32)    = S + A [32-bit only]
    /// R_SPARC_TLS_DTPMOD32     (V-word32)    = @dtpmod(S + A)
    /// R_SPARC_TLS_DTPOFF32     (V-word32)    = @dtpoff(S + A)
    /// R_SPARC_TLS_TPOFF32      (V-word32)    = @tpoff(S + A)
    /// R_SPARC_SIZE32           (V-word32)    = Z + A
    pub const Word32 = packed struct(u32) {
        word32: u32,
    };

    /// R_SPARC_GLOB_DAT         (V-word64)    = S + A [64-bit only]
    /// R_SPARC_64               (V-word64)    = S + A
    /// R_SPARC_DISP64           (V-word64)    = S + A - P
    /// R_SPARC_PLT64            (V-word64)    = L + A
    /// R_SPARC_REGISTER         (V-word64)    = S + A [64-bit only]
    /// R_SPARC_UA64             (V-word64)    = S + A
    /// R_SPARC_TLS_DTPMOD64     (V-word64)    = @dtpmod(S + A)
    /// R_SPARC_TLS_DTPOFF64     (V-word64)    = @dtpoff(S + A)
    /// R_SPARC_TLS_TPOFF64      (V-word64)    = @tpoff(S + A)
    /// R_SPARC_SIZE64           (V-word64)    = Z + A
    pub const Word64 = packed struct(u64) {
        word64: u64,
    };

    /// R_SPARC_5                (V-imm5)      = S + A
    pub const Imm5 = packed struct(u32) {
        imm5: u5,
        b5_31: u27,
    };

    /// R_SPARC_6                (V-imm6)      = S + A
    pub const Imm6 = packed struct(u32) {
        imm6: u6,
        b6_31: u26,
    };

    /// R_SPARC_7                (V-imm7)      = S + A
    pub const Imm7 = packed struct(u32) {
        imm7: u7,
        b7_31: u25,
    };

    /// R_SPARC_M44              (T-imm10)     = ((S + A) >> 12) & 0x3ff
    pub const Imm10 = packed struct(u32) {
        imm10: u10,
        b10_31: u22,
    };

    /// R_SPARC_10               (V-simm10)    = S + A
    pub const Simm10 = packed struct(u32) {
        simm10: u10,
        b10_31: u22,
    };

    /// R_SPARC_11               (V-simm11)    = S + A
    pub const Simm11 = packed struct(u32) {
        simm11: u11,
        b11_31: u21,
    };

    /// R_SPARC_L44              (T-imm13)     = (S + A) & 0xfff
    /// R_SPARC_GOTDATA_LOX10    (T-imm13)     = ((S + A - GOT) & 0x3ff) | (((S + A - GOT) >> 31) & 0x1c00)
    /// R_SPARC_GOTDATA_OP_LOX10 (T-imm13)     = (G & 0x3ff) | ((G >> 31) & 0x1c00)
    pub const Imm13 = packed struct(u32) {
        imm13: u13,
        b13_31: u19,
    };

    /// R_SPARC_13               (V-simm13)    = S + A
    /// R_SPARC_LO10             (T-simm13)    = (S + A) & 0x3ff
    /// R_SPARC_GOT10            (T-simm13)    = G & 0x3ff
    /// R_SPARC_GOT13            (V-simm13)    = G
    /// R_SPARC_PC10             (T-simm13)    = (S + A - P) & 0x3ff
    /// R_SPARC_LOPLT10          (T-simm13)    = (L + A) & 0x3ff
    /// R_SPARC_PCPLT10          (V-simm13)    = (L + A - P) & 0x3ff
    /// R_SPARC_OLO10            (V-simm13)    = ((S + A) & 0x3ff) + O
    /// R_SPARC_HM10             (T-simm13)    = ((S + A) >> 32) & 0x3ff
    /// R_SPARC_PC_HM10          (T-simm13)    = ((S + A - P) >> 32) & 0x3ff
    /// R_SPARC_LOX10            (T-simm13)    = ((S + A) & 0x3ff) | 0x1c00
    /// R_SPARC_TLS_GD_LO10      (T-simm13)    = @dtlndx(S + A) & 0x3ff
    /// R_SPARC_TLS_LDM_LO10     (T-simm13)    = @tmndx(S + A) & 0x3ff
    /// R_SPARC_TLS_LDO_LOX10    (T-simm13)    = @dtpoff(S + A) & 0x3ff
    /// R_SPARC_TLS_IE_LO10      (T-simm13)    = @got(@tpoff(S + A)) & 0x3ff
    /// R_SPARC_TLS_LE_LOX10     (T-simm13)    = (@tpoff(S + A) & 0x3ff) | 0x1c00
    pub const Simm13 = packed struct(u32) {
        simm13: u13,
        b13_31: u19,
    };

    /// R_SPARC_HI22             (T-imm22)     = (S + A) >> 10 [32-bit only]
    /// R_SPARC_HI22             (V-imm22)     = (S + A) >> 10 [64-bit only]
    /// R_SPARC_22               (V-imm22)     = S + A
    /// R_SPARC_HIPLT22          (T-imm22)     = (L + A) >> 10
    /// R_SPARC_HH22             (V-imm22)     = (S + A) >> 42
    /// R_SPARC_LM22             (T-imm22)     = (S + A) >> 10
    /// R_SPARC_PC_HH22          (V-imm22)     = (S + A - P) >> 42
    /// R_SPARC_PC_LM22          (T-imm22)     = (S + A - P) >> 10
    /// R_SPARC_HIX22            (V-imm22)     = ((S + A) ^ 0xffffffffffffffff) >> 10
    /// R_SPARC_H44              (V-imm22)     = (S + A) >> 22
    /// R_SPARC_TLS_LE_HIX22     (T-imm22)     = (@tpoff(S + A) ^ 0xffffffffffffffff) >> 10
    /// R_SPARC_GOTDATA_HIX22    (V-imm22)     = ((S + A - GOT) >> 10) ^ ((S + A - GOT) >> 31)
    /// R_SPARC_GOTDATA_OP_HIX22 (T-imm22)     = (G >> 10) ^ (G >> 31)
    /// R_SPARC_H34              (V-imm22)     = (S + A) >> 12
    pub const Imm22 = packed struct(u32) {
        imm22: u22,
        b22_31: u10,
    };

    /// R_SPARC_GOT22            (T-simm22)    = G >> 10
    /// R_SPARC_TLS_GD_HI22      (T-simm22)    = @dtlndx(S + A) >> 10
    /// R_SPARC_TLS_LDM_HI22     (T-simm22)    = @tmndx(S + A) >> 10
    /// R_SPARC_TLS_LDO_HIX22    (T-simm22)    = @dtpoff(S + A) >> 10
    /// R_SPARC_TLS_IE_HI22      (T-simm22)    = @got(@tpoff(S + A)) >> 10
    pub const Simm22 = packed struct(u32) {
        simm22: u22,
        b22_31: u10,
    };

    /// R_SPARC_WDISP19          (V-disp19)    = (S + A - P) >> 2
    pub const Disp19 = packed struct(u32) {
        disp19: u19,
        b19_31: u13,
    };

    /// R_SPARC_WDISP22          (V-disp22)    = (S + A - P) >> 2
    /// R_SPARC_PC22             (V-disp22)    = (S + A - P) >> 10
    /// R_SPARC_PCPLT22          (V-disp22)    = (L + A - P) >> 10
    pub const Disp22 = packed struct(u32) {
        disp22: u22,
        b22_31: u10,
    };

    /// R_SPARC_WDISP30          (V-disp30)    = (S + A - P) >> 2
    /// R_SPARC_WPLT30           (V-disp30)    = (L + A - P) >> 2
    /// R_SPARC_TLS_GD_CALL      (V-disp30)    = (L + A - P) >> 2
    /// R_SPARC_TLS_LDM_CALL     (V-disp30)    = (L + A - P) >> 2
    pub const Disp30 = packed struct(u32) {
        disp30: u30,
        b30_31: u2,
    };

    /// R_SPARC_DISP32           (V-disp32)    = S + A - P
    pub const Disp32 = packed struct(u32) {
        disp32: u32,
    };

    /// R_SPARC_WDISP10          (V-d2/disp8)  = (S + A - P) >> 2
    pub const D2Disp8 = packed struct(u32) {
        b0_3: u4,
        disp8: u8,
        b12_17: u6,
        d2: u2,
        b20_31: u12,
    };

    /// R_SPARC_WDISP16          (V-d2/disp14) = (S + A - P) >> 2
    pub const D2Disp14 = packed struct(u32) {
        disp14: u14,
        b14_19: u6,
        d2: u2,
        b22_31: u10,
    };
};
