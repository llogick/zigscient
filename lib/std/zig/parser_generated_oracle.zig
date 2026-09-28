//! This file is generated, do not edit manually! To generate, run:
//! zig build gen-parser-oracle

const std = @import("std");

const Error = error{MaxDepth};
const max_depth = 5;

/// Returns true if the input source is in the language defined by
/// the grammar.
/// Returns error.MaxDepth if more than `max_depth` levels of recursion/iteration are reached.
pub fn parse(source: []const u8) Error!bool {
    var p: Parser = .{ .source = source, .i = 0, .depths = @splat(1) };
    return p.parseRoot();
}
const Def = enum {
    defRoot,
    defContainerMembers,
    defContainerMembersRest,
    defContainerDecl,
    defContainerDeclPrefix,
    defTestDecl,
    defComptimeDecl,
    defDecl,
    defDeclPrefix,
    defFnProto,
    defVarDeclProto,
    defGlobalVarDecl,
    defContainerField,
    defBlockStatement,
    defStatement,
    defStatementPrefix,
    defIfStatement,
    defLabeledStatement,
    defLoopStatement,
    defForStatement,
    defWhileStatement,
    defBlockExprStatement,
    defBlockExprPrefix,
    defBlockExpr,
    defVarAssignStatement,
    defAssignExpr,
    defSingleAssignExpr,
    defExpr,
    defBoolOrExpr,
    defBoolAndExpr,
    defCompareExpr,
    defBitwiseExpr,
    defBitShiftExpr,
    defAdditionExpr,
    defMultiplyExpr,
    defPrefixExpr,
    defPrimaryExpr,
    defIfExpr,
    defBlock,
    defLoopExpr,
    defForExpr,
    defWhileExpr,
    defCurlySuffixExpr,
    defInitList,
    defTypeExpr,
    defErrorUnionExpr,
    defSuffixExpr,
    defPrimaryTypeExpr,
    defContainerType,
    defErrorSetDecl,
    defGroupedExpr,
    defIfTypeExpr,
    defLabeledTypeExpr,
    defLoopTypeExpr,
    defForTypeExpr,
    defWhileTypeExpr,
    defSwitchExpr,
    defAsmExpr,
    defAsmOutput,
    defAsmOutputItem,
    defAsmInput,
    defAsmInputItem,
    defAsmClobbers,
    defBreakLabel,
    defBlockLabel,
    defFieldInit,
    defWhileContinueExpr,
    defLinkSection,
    defAddrSpace,
    defCallConv,
    defParamDecl,
    defParamType,
    defIfPrefix,
    defWhilePrefix,
    defForPrefix,
    defPayload,
    defPtrPayload,
    defPtrIndexPayload,
    defPtrListPayload,
    defSwitchProng,
    defSwitchCase,
    defSwitchItem,
    defForArgumentsList,
    defForItem,
    defAssignOp,
    defOrOp,
    defAndOp,
    defCompareOp,
    defCompareOpTok,
    defBitwiseOp,
    defBitwiseOpTok,
    defBitShiftOp,
    defBitShiftOpTok,
    defAdditionOp,
    defAdditionOpTok,
    defMultiplyOp,
    defMultiplyOpTok,
    defPrefixOp,
    defPrefixTypeOp,
    defPtrMods,
    defSinglePtrMods,
    defPtrMod,
    defPrefixTypeOpPrefix,
    defSuffixOp,
    defSuffixOpPrefix,
    defFnCallArguments,
    defSliceTypeStart,
    defSinglePtrTypeStart,
    defManyPtrTypeStart,
    defArrayTypeStart,
    defContainerTypeAuto,
    defContainerTypeKind,
    defByteAlign,
    defBitAlign,
    defIdentifierList,
    defSwitchProngList,
    defAsmOutputList,
    defAsmInputList,
    defParamDeclList,
    defParamDeclListRest,
    defExprList,
    defExprPrefix,
    defbyte_order_mark,
    defsof,
    defeof,
    defox80_oxBF,
    defoxF4,
    defox80_ox8F,
    defoxF1_oxF3,
    defoxF0,
    defox90_0xBF,
    defoxEE_oxEF,
    defoxED,
    defox80_ox9F,
    defoxE1_oxEC,
    defoxE0,
    defoxA0_oxBF,
    defoxC2_oxDF,
    defmultibyte_utf8,
    defnon_control_ascii,
    defnon_control_utf8,
    defchar_char,
    defstring_char,
    defcontainer_doc_comment,
    defdoc_comment,
    defline_comment,
    defline_string,
    defnewline,
    defskip,
    defskip_require_newline,
    defpre_op_white,
    defpost_op_white,
    defCHAR_LITERAL,
    defdigit,
    defdigit_int,
    defdigit_float,
    defNUMBERLITERAL,
    defstring,
    defSTRINGLITERALSINGLE,
    defSTRINGLITERAL,
    defIDENTIFIER,
    defBUILTINIDENTIFIER,
    defAMPERSAND,
    defAMPERSANDEQUAL,
    defASTERISK,
    defASTERISKEQUAL,
    defASTERISKPERCENT,
    defASTERISKPERCENTEQUAL,
    defASTERISKPIPE,
    defASTERISKPIPEEQUAL,
    defCARET,
    defCARETEQUAL,
    defCOLON,
    defCOMMA,
    defDOT,
    defDOT2,
    defDOT3,
    defDOTASTERISK,
    defEQUAL,
    defEQUALEQUAL,
    defEQUALRARROW,
    defEXCLAMATIONMARK,
    defEXCLAMATIONMARKEQUAL,
    defLARROW,
    defLARROW2,
    defLARROW2EQUAL,
    defLARROW2PIPE,
    defLARROW2PIPEEQUAL,
    defLARROWEQUAL,
    defLBRACE,
    defLBRACKET,
    defLPAREN,
    defMINUS,
    defMINUSEQUAL,
    defMINUSPERCENT,
    defMINUSPERCENTEQUAL,
    defMINUSPIPE,
    defMINUSPIPEEQUAL,
    defMINUSRARROW,
    defPERCENT,
    defPERCENTEQUAL,
    defPIPE,
    defPIPE2,
    defPIPEEQUAL,
    defPLUS,
    defPLUS2,
    defPLUSEQUAL,
    defPLUSPERCENT,
    defPLUSPERCENTEQUAL,
    defPLUSPIPE,
    defPLUSPIPEEQUAL,
    defLETTERC,
    defQUESTIONMARK,
    defRARROW,
    defRARROW2,
    defRARROW2EQUAL,
    defRARROWEQUAL,
    defRBRACE,
    defRBRACKET,
    defRPAREN,
    defSEMICOLON,
    defSLASH,
    defSLASHEQUAL,
    defTILDE,
    defend_of_word,
    defKEYWORD_addrspace,
    defKEYWORD_align,
    defKEYWORD_allowzero,
    defKEYWORD_and,
    defKEYWORD_anyframe,
    defKEYWORD_anytype,
    defKEYWORD_asm,
    defKEYWORD_break,
    defKEYWORD_callconv,
    defKEYWORD_catch,
    defKEYWORD_comptime,
    defKEYWORD_const,
    defKEYWORD_continue,
    defKEYWORD_defer,
    defKEYWORD_else,
    defKEYWORD_enum,
    defKEYWORD_errdefer,
    defKEYWORD_error,
    defKEYWORD_export,
    defKEYWORD_extern,
    defKEYWORD_fn,
    defKEYWORD_for,
    defKEYWORD_if,
    defKEYWORD_inline,
    defKEYWORD_noalias,
    defKEYWORD_nosuspend,
    defKEYWORD_noinline,
    defKEYWORD_opaque,
    defKEYWORD_or,
    defKEYWORD_orelse,
    defKEYWORD_packed,
    defKEYWORD_pub,
    defKEYWORD_resume,
    defKEYWORD_return,
    defKEYWORD_linksection,
    defKEYWORD_struct,
    defKEYWORD_suspend,
    defKEYWORD_switch,
    defKEYWORD_test,
    defKEYWORD_threadlocal,
    defKEYWORD_try,
    defKEYWORD_union,
    defKEYWORD_unreachable,
    defKEYWORD_var,
    defKEYWORD_volatile,
    defKEYWORD_while,
    defkeyword,
};
const Parser = struct {
    source: []const u8,
    i: usize,
    depths: [272]u8,
    pub fn parseRoot(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defRoot);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseContainerMembers() and try p.parseskip() and try p.parseeof()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseContainerMembers(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defContainerMembers);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((try p.parsecontainer_doc_comment() or true) and blk_1: {
                var i_1: usize = 0;
                while (try p.parseContainerDecl()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and try p.parseContainerMembersRest()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseContainerMembersRest(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defContainerMembersRest);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseContainerDeclPrefix();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseContainerField() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseCOMMA() and try p.parseContainerMembersRest()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true)) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                var i_1: usize = 0;
                while (try p.parseContainerDecl()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseContainerDecl(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defContainerDecl);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseTestDecl()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseComptimeDecl()) break :blk_0 true;
            p.i = pos_0;
            if ((try p.parsedoc_comment() or true) and (try p.parseKEYWORD_pub() or true) and try p.parseDecl()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseContainerDeclPrefix(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defContainerDeclPrefix);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_test()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_comptime() and try p.parseLBRACE()) break :blk_0 true;
            p.i = pos_0;
            if ((try p.parsedoc_comment() or true) and (try p.parseKEYWORD_pub() or true) and try p.parseDeclPrefix()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseTestDecl(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defTestDecl);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_test() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseSTRINGLITERALSINGLE()) break :blk_3 true;
                p.i = pos_3;
                if (try p.parseIDENTIFIER()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and try p.parseBlock()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseComptimeDecl(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defComptimeDecl);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_comptime() and try p.parseBlock()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseDecl(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defDecl);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((blk_3: {
                const pos_3 = p.i;
                if (try p.parseKEYWORD_export()) break :blk_3 true;
                p.i = pos_3;
                if (try p.parseKEYWORD_inline()) break :blk_3 true;
                p.i = pos_3;
                if (try p.parseKEYWORD_noinline()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and try p.parseFnProto() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseSEMICOLON()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseBlock()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_extern() and (try p.parseSTRINGLITERALSINGLE() or true) and try p.parseFnProto() and try p.parseSEMICOLON()) break :blk_0 true;
            p.i = pos_0;
            if ((blk_3: {
                const pos_3 = p.i;
                if (try p.parseKEYWORD_export()) break :blk_3 true;
                p.i = pos_3;
                if (try p.parseKEYWORD_extern() and (try p.parseSTRINGLITERALSINGLE() or true)) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and (try p.parseKEYWORD_threadlocal() or true) and try p.parseGlobalVarDecl()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseDeclPrefix(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defDeclPrefix);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((blk_3: {
                const pos_3 = p.i;
                if (try p.parseKEYWORD_export()) break :blk_3 true;
                p.i = pos_3;
                if (try p.parseKEYWORD_inline()) break :blk_3 true;
                p.i = pos_3;
                if (try p.parseKEYWORD_noinline()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and try p.parseKEYWORD_fn()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_extern() and (try p.parseSTRINGLITERALSINGLE() or true) and try p.parseKEYWORD_fn()) break :blk_0 true;
            p.i = pos_0;
            if ((blk_3: {
                const pos_3 = p.i;
                if (try p.parseKEYWORD_export()) break :blk_3 true;
                p.i = pos_3;
                if (try p.parseKEYWORD_extern() and (try p.parseSTRINGLITERALSINGLE() or true)) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and (try p.parseKEYWORD_threadlocal() or true) and blk_2: {
                const pos_2 = p.i;
                if (try p.parseKEYWORD_const()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseKEYWORD_var()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseFnProto(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defFnProto);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_fn() and (try p.parseIDENTIFIER() or true) and try p.parseParamDeclList() and (try p.parseByteAlign() or true) and (try p.parseAddrSpace() or true) and (try p.parseLinkSection() or true) and (try p.parseCallConv() or true) and (try p.parseEXCLAMATIONMARK() or true) and try p.parseTypeExpr()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseVarDeclProto(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defVarDeclProto);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_2: {
                const pos_2 = p.i;
                if (try p.parseKEYWORD_const()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseKEYWORD_var()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            } and try p.parseIDENTIFIER() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseCOLON() and try p.parseTypeExpr()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and (try p.parseByteAlign() or true) and (try p.parseAddrSpace() or true) and (try p.parseLinkSection() or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseGlobalVarDecl(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defGlobalVarDecl);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseVarDeclProto() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseEQUAL() and try p.parseExpr()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and try p.parseSEMICOLON()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseContainerField(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defContainerField);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((try p.parsedoc_comment() or true) and (try p.parseKEYWORD_comptime() or true) and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseIDENTIFIER() and try p.parseCOLON()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and try p.parseTypeExpr() and (try p.parseByteAlign() or true) and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseEQUAL() and try p.parseExpr()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBlockStatement(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBlockStatement);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseStatement()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_defer() and try p.parseBlockExprStatement()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_errdefer() and try p.parseBlockExprStatement()) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseStatementPrefix();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and (try p.parseKEYWORD_comptime() or true) and try p.parseVarAssignStatement()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseStatement(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defStatement);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseIfStatement()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseLabeledStatement()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_nosuspend() and try p.parseBlockExprStatement()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_comptime() and try p.parseBlockExpr()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_suspend() and try p.parseBlockExprStatement()) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseStatementPrefix();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and (try p.parseKEYWORD_comptime() or true) and try p.parseAssignExpr() and try p.parseSEMICOLON()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseStatementPrefix(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defStatementPrefix);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_if()) break :blk_0 true;
            p.i = pos_0;
            if ((try p.parseBlockLabel() or true) and blk_2: {
                const pos_2 = p.i;
                if (try p.parseLBRACE()) break :blk_2 true;
                p.i = pos_2;
                if ((try p.parseKEYWORD_inline() or true) and blk_4: {
                    const pos_4 = p.i;
                    if (try p.parseKEYWORD_for()) break :blk_4 true;
                    p.i = pos_4;
                    if (try p.parseKEYWORD_while()) break :blk_4 true;
                    p.i = pos_4;
                    break :blk_4 false;
                }) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseKEYWORD_switch()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_nosuspend()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_comptime() and try p.parseBlockExprPrefix()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseIfStatement(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defIfStatement);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseIfPrefix() and try p.parseBlockExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseKEYWORD_else() and (try p.parsePayload() or true) and try p.parseStatement()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseKEYWORD_else();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseIfPrefix() and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseBlockExprPrefix();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseAssignExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseSEMICOLON()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseKEYWORD_else() and (try p.parsePayload() or true) and try p.parseStatement()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLabeledStatement(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLabeledStatement);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((try p.parseBlockLabel() or true) and blk_2: {
                const pos_2 = p.i;
                if (try p.parseBlock()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseLoopStatement()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseSwitchExpr()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLoopStatement(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLoopStatement);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((try p.parseKEYWORD_inline() or true) and blk_2: {
                const pos_2 = p.i;
                if (try p.parseForStatement()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseWhileStatement()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseForStatement(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defForStatement);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseForPrefix() and try p.parseBlockExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseKEYWORD_else() and try p.parseStatement()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseKEYWORD_else();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseForPrefix() and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseBlockExprPrefix();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseAssignExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseSEMICOLON()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseKEYWORD_else() and try p.parseStatement()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseWhileStatement(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defWhileStatement);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseWhilePrefix() and try p.parseBlockExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseKEYWORD_else() and (try p.parsePayload() or true) and try p.parseStatement()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseKEYWORD_else();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseWhilePrefix() and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseBlockExprPrefix();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseAssignExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseSEMICOLON()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseKEYWORD_else() and (try p.parsePayload() or true) and try p.parseStatement()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBlockExprStatement(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBlockExprStatement);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseBlockExpr()) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseBlockExprPrefix();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseAssignExpr() and try p.parseSEMICOLON()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBlockExprPrefix(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBlockExprPrefix);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((try p.parseBlockLabel() or true) and try p.parseLBRACE()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBlockExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBlockExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((try p.parseBlockLabel() or true) and try p.parseBlock()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseVarAssignStatement(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defVarAssignStatement);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_2: {
                const pos_2 = p.i;
                if (try p.parseVarDeclProto()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseExpr()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            } and blk_1: {
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseCOMMA() and blk_5: {
                        const pos_5 = p.i;
                        if (try p.parseVarDeclProto()) break :blk_5 true;
                        p.i = pos_5;
                        if (try p.parseExpr()) break :blk_5 true;
                        p.i = pos_5;
                        break :blk_5 false;
                    }) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and try p.parseEQUAL() and try p.parseExpr() and try p.parseSEMICOLON()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAssignExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAssignExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseAssignOp() and try p.parseExpr()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    var match_3 = false;
                    var i_3: usize = 0;
                    while (blk_5: {
                        const pos_5 = p.i;
                        if (try p.parseCOMMA() and try p.parseExpr()) break :blk_5 true;
                        p.i = pos_5;
                        break :blk_5 false;
                    }) {
                        match_3 = true;
                        if (i_3 > max_depth) return error.MaxDepth;
                        i_3 += 1;
                    }
                    break :blk_3 match_3;
                } and try p.parseEQUAL() and try p.parseExpr()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseAssignOp();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                } and blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseCOMMA();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSingleAssignExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSingleAssignExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseAssignOp() and try p.parseExpr()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseAssignOp();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseBoolOrExpr()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBoolOrExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBoolOrExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseBoolAndExpr() and blk_1: {
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseOrOp() and try p.parseBoolAndExpr()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseOrOp();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBoolAndExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBoolAndExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseCompareExpr() and blk_1: {
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseAndOp() and try p.parseCompareExpr()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseAndOp();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseCompareExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defCompareExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseBitwiseExpr() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseCompareOp() and try p.parseBitwiseExpr()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseCompareOp();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBitwiseExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBitwiseExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseBitShiftExpr() and blk_1: {
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseBitwiseOp() and try p.parseBitShiftExpr()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseBitwiseOp();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBitShiftExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBitShiftExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseAdditionExpr() and blk_1: {
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseBitShiftOp() and try p.parseAdditionExpr()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseBitShiftOp();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAdditionExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAdditionExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseMultiplyExpr() and blk_1: {
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseAdditionOp() and try p.parseMultiplyExpr()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseAdditionOp();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseMultiplyExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defMultiplyExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsePrefixExpr() and blk_1: {
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseMultiplyOp() and try p.parsePrefixExpr()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseMultiplyOp();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePrefixExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPrefixExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                var i_1: usize = 0;
                while (try p.parsePrefixOp()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsePrefixOp();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parsePrimaryExpr()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePrimaryExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPrimaryExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseAsmExpr()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseIfExpr()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_break() and (try p.parseBreakLabel() or true) and blk_2: {
                const pos_2 = p.i;
                if (try p.parseExpr()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseExprPrefix();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_comptime() and try p.parseExpr()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_nosuspend() and try p.parseExpr()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_continue() and (try p.parseBreakLabel() or true) and blk_2: {
                const pos_2 = p.i;
                if (try p.parseExpr()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseExprPrefix();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_resume() and try p.parseExpr()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_return() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseExpr()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseExprPrefix();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            if ((try p.parseBlockLabel() or true) and try p.parseLoopExpr()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseBlock()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseCurlySuffixExpr()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseIfExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defIfExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseIfPrefix() and try p.parseExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseKEYWORD_else() and (try p.parsePayload() or true) and try p.parseExpr()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseKEYWORD_else();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBlock(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBlock);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseLBRACE() and blk_1: {
                var i_1: usize = 0;
                while (try p.parseBlockStatement()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and try p.parseRBRACE()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLoopExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLoopExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((try p.parseKEYWORD_inline() or true) and blk_2: {
                const pos_2 = p.i;
                if (try p.parseForExpr()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseWhileExpr()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseForExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defForExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseForPrefix() and try p.parseExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseKEYWORD_else() and try p.parseExpr()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseKEYWORD_else();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseWhileExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defWhileExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseWhilePrefix() and try p.parseExpr() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseKEYWORD_else() and (try p.parsePayload() or true) and try p.parseExpr()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseCurlySuffixExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defCurlySuffixExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseTypeExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseInitList()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseLBRACE();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseInitList(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defInitList);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseLBRACE() and try p.parseFieldInit() and blk_1: {
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseCOMMA() and try p.parseFieldInit()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and (try p.parseCOMMA() or true) and try p.parseRBRACE()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseLBRACE() and try p.parseExpr() and blk_1: {
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseCOMMA() and try p.parseExpr()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and (try p.parseCOMMA() or true) and try p.parseRBRACE()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseLBRACE() and try p.parseRBRACE()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseTypeExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defTypeExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                var i_1: usize = 0;
                while (try p.parsePrefixTypeOp()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsePrefixTypeOpPrefix();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseErrorUnionExpr()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseErrorUnionExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defErrorUnionExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseSuffixExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseEXCLAMATIONMARK() and try p.parseTypeExpr()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseEXCLAMATIONMARK();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSuffixExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSuffixExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsePrimaryTypeExpr() and blk_1: {
                var i_1: usize = 0;
                while (try p.parseSuffixOp()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseSuffixOpPrefix();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePrimaryTypeExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPrimaryTypeExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseBUILTINIDENTIFIER() and try p.parseFnCallArguments()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseCHAR_LITERAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseContainerType()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseDOT() and try p.parseIDENTIFIER()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseDOT() and try p.parseInitList()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseErrorSetDecl()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseFnProto()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseGroupedExpr()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseLabeledTypeExpr()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseIDENTIFIER()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseIfTypeExpr()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_comptime() and try p.parseTypeExpr()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_error() and try p.parseDOT() and try p.parseIDENTIFIER()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_anyframe()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_unreachable()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseNUMBERLITERAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseSTRINGLITERAL()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseContainerType(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defContainerType);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((blk_3: {
                const pos_3 = p.i;
                if (try p.parseKEYWORD_extern()) break :blk_3 true;
                p.i = pos_3;
                if (try p.parseKEYWORD_packed()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and try p.parseContainerTypeAuto()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseErrorSetDecl(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defErrorSetDecl);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_error() and try p.parseLBRACE() and try p.parseIdentifierList() and try p.parseRBRACE()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseGroupedExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defGroupedExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseLPAREN() and try p.parseExpr() and try p.parseRPAREN()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseIfTypeExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defIfTypeExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseIfPrefix() and try p.parseTypeExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseKEYWORD_else() and (try p.parsePayload() or true) and try p.parseTypeExpr()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseKEYWORD_else();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLabeledTypeExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLabeledTypeExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseBlockLabel() and try p.parseBlock()) break :blk_0 true;
            p.i = pos_0;
            if ((try p.parseBlockLabel() or true) and try p.parseLoopTypeExpr()) break :blk_0 true;
            p.i = pos_0;
            if ((try p.parseBlockLabel() or true) and try p.parseSwitchExpr()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLoopTypeExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLoopTypeExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((try p.parseKEYWORD_inline() or true) and blk_2: {
                const pos_2 = p.i;
                if (try p.parseForTypeExpr()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseWhileTypeExpr()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseForTypeExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defForTypeExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseForPrefix() and try p.parseTypeExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseKEYWORD_else() and try p.parseTypeExpr()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseKEYWORD_else();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseWhileTypeExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defWhileTypeExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseWhilePrefix() and try p.parseTypeExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseKEYWORD_else() and (try p.parsePayload() or true) and try p.parseTypeExpr()) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseKEYWORD_else();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSwitchExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSwitchExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_switch() and try p.parseLPAREN() and try p.parseExpr() and try p.parseRPAREN() and try p.parseLBRACE() and try p.parseSwitchProngList() and try p.parseRBRACE()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAsmExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAsmExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_asm() and (try p.parseKEYWORD_volatile() or true) and try p.parseLPAREN() and try p.parseExpr() and (try p.parseAsmOutput() or true) and try p.parseRPAREN()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAsmOutput(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAsmOutput);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseCOLON() and try p.parseAsmOutputList() and (try p.parseAsmInput() or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAsmOutputItem(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAsmOutputItem);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseLBRACKET() and try p.parseIDENTIFIER() and try p.parseRBRACKET() and try p.parseSTRINGLITERALSINGLE() and try p.parseLPAREN() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseMINUSRARROW() and try p.parseTypeExpr()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseIDENTIFIER()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            } and try p.parseRPAREN()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAsmInput(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAsmInput);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseCOLON() and try p.parseAsmInputList() and (try p.parseAsmClobbers() or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAsmInputItem(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAsmInputItem);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseLBRACKET() and try p.parseIDENTIFIER() and try p.parseRBRACKET() and try p.parseSTRINGLITERALSINGLE() and try p.parseLPAREN() and try p.parseExpr() and try p.parseRPAREN()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAsmClobbers(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAsmClobbers);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseCOLON() and try p.parseExpr()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBreakLabel(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBreakLabel);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseCOLON() and try p.parseIDENTIFIER()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBlockLabel(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBlockLabel);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseIDENTIFIER() and try p.parseCOLON()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseFieldInit(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defFieldInit);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseDOT() and try p.parseIDENTIFIER() and try p.parseEQUAL() and try p.parseExpr()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseWhileContinueExpr(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defWhileContinueExpr);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseCOLON() and try p.parseLPAREN() and try p.parseAssignExpr() and try p.parseRPAREN()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLinkSection(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLinkSection);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_linksection() and try p.parseLPAREN() and try p.parseExpr() and try p.parseRPAREN()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAddrSpace(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAddrSpace);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_addrspace() and try p.parseLPAREN() and try p.parseExpr() and try p.parseRPAREN()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseCallConv(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defCallConv);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_callconv() and try p.parseLPAREN() and try p.parseExpr() and try p.parseRPAREN()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseParamDecl(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defParamDecl);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((try p.parsedoc_comment() or true) and blk_2: {
                const pos_2 = p.i;
                if (try p.parseKEYWORD_noalias()) break :blk_2 true;
                p.i = pos_2;
                if ((try p.parseKEYWORD_comptime() or true)) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            } and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseIDENTIFIER() and try p.parseCOLON()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and try p.parseParamType()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseParamType(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defParamType);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_anytype()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseTypeExpr()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseIfPrefix(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defIfPrefix);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_if() and try p.parseLPAREN() and try p.parseExpr() and try p.parseRPAREN() and (try p.parsePtrPayload() or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseWhilePrefix(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defWhilePrefix);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_while() and try p.parseLPAREN() and try p.parseExpr() and try p.parseRPAREN() and (try p.parsePtrPayload() or true) and (try p.parseWhileContinueExpr() or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseForPrefix(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defForPrefix);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_for() and try p.parseLPAREN() and try p.parseForArgumentsList() and try p.parseRPAREN() and try p.parsePtrListPayload()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePayload(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPayload);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsePIPE() and try p.parseIDENTIFIER() and try p.parsePIPE()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePtrPayload(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPtrPayload);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsePIPE() and (try p.parseASTERISK() or true) and try p.parseIDENTIFIER() and try p.parsePIPE()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePtrIndexPayload(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPtrIndexPayload);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsePIPE() and (try p.parseASTERISK() or true) and try p.parseIDENTIFIER() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseCOMMA() and try p.parseIDENTIFIER()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and try p.parsePIPE()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePtrListPayload(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPtrListPayload);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsePIPE() and (try p.parseASTERISK() or true) and try p.parseIDENTIFIER() and blk_1: {
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseCOMMA() and (try p.parseASTERISK() or true) and try p.parseIDENTIFIER()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and (try p.parseCOMMA() or true) and try p.parsePIPE()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSwitchProng(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSwitchProng);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((try p.parseKEYWORD_inline() or true) and try p.parseSwitchCase() and try p.parseEQUALRARROW() and (try p.parsePtrIndexPayload() or true) and try p.parseSingleAssignExpr()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSwitchCase(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSwitchCase);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseSwitchItem() and blk_1: {
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseCOMMA() and try p.parseSwitchItem()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and (try p.parseCOMMA() or true)) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_else()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSwitchItem(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSwitchItem);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseExpr() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseDOT3() and try p.parseExpr()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseForArgumentsList(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defForArgumentsList);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseForItem() and blk_1: {
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseCOMMA() and try p.parseForItem()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and (try p.parseCOMMA() or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseForItem(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defForItem);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseExpr() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseDOT2() and blk_4: {
                    const pos_4 = p.i;
                    if (try p.parseExpr()) break :blk_4 true;
                    p.i = pos_4;
                    if (blk_5: {
                        const pos_5 = p.i;
                        const match_5 = try p.parseExprPrefix();
                        p.i = pos_5;
                        break :blk_5 !match_5;
                    }) break :blk_4 true;
                    p.i = pos_4;
                    break :blk_4 false;
                }) break :blk_2 true;
                p.i = pos_2;
                if (blk_3: {
                    const pos_3 = p.i;
                    const match_3 = try p.parseDOT2();
                    p.i = pos_3;
                    break :blk_3 !match_3;
                }) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAssignOp(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAssignOp);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseASTERISKEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseASTERISKPIPEEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseSLASHEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parsePERCENTEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parsePLUSEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parsePLUSPIPEEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseMINUSEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseMINUSPIPEEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseLARROW2EQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseLARROW2PIPEEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseRARROW2EQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseAMPERSANDEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseCARETEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parsePIPEEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseASTERISKPERCENTEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parsePLUSPERCENTEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseMINUSPERCENTEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseEQUAL()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseOrOp(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defOrOp);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsepre_op_white() and try p.parseKEYWORD_or() and try p.parsepost_op_white()) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepre_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseKEYWORD_or() and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepost_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAndOp(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAndOp);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsepre_op_white() and try p.parseKEYWORD_and() and try p.parsepost_op_white()) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepre_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseKEYWORD_and() and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepost_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseCompareOp(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defCompareOp);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsepre_op_white() and try p.parseCompareOpTok() and try p.parsepost_op_white()) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepre_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseCompareOpTok() and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepost_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseCompareOpTok(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defCompareOpTok);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseEQUALEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseEXCLAMATIONMARKEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseLARROW()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseRARROW()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseLARROWEQUAL()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseRARROWEQUAL()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBitwiseOp(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBitwiseOp);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsepre_op_white() and try p.parseBitwiseOpTok() and try p.parsepost_op_white()) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepre_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseBitwiseOpTok() and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepost_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            if (try p.parsepre_op_white() and try p.parseKEYWORD_catch() and try p.parsepost_op_white() and (try p.parsePayload() or true)) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepre_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseKEYWORD_catch() and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepost_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and (try p.parsePayload() or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBitwiseOpTok(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBitwiseOpTok);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseAMPERSAND() and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '&'...'&',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseCARET()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parsePIPE()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_orelse()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBitShiftOp(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBitShiftOp);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsepre_op_white() and try p.parseBitShiftOpTok() and try p.parsepost_op_white()) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepre_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseBitShiftOpTok() and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepost_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBitShiftOpTok(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBitShiftOpTok);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseLARROW2()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseRARROW2()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseLARROW2PIPE()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAdditionOp(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAdditionOp);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsepre_op_white() and try p.parseAdditionOpTok() and try p.parsepost_op_white()) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepre_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseAdditionOpTok() and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepost_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAdditionOpTok(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAdditionOpTok);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsePLUS()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseMINUS()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parsePLUS2()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parsePLUSPERCENT()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseMINUSPERCENT()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parsePLUSPIPE()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseMINUSPIPE()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseMultiplyOp(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defMultiplyOp);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsepre_op_white() and try p.parseMultiplyOpTok() and try p.parsepost_op_white()) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepre_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseMultiplyOpTok() and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsepost_op_white();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseMultiplyOpTok(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defMultiplyOpTok);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsePIPE2()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseASTERISK()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseSLASH()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parsePERCENT()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseASTERISKPERCENT()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseASTERISKPIPE()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePrefixOp(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPrefixOp);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseEXCLAMATIONMARK()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseMINUS()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseTILDE()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseMINUSPERCENT()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseAMPERSAND()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_try()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePrefixTypeOp(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPrefixTypeOp);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseQUESTIONMARK()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_anyframe() and try p.parseMINUSRARROW()) break :blk_0 true;
            p.i = pos_0;
            if (blk_2: {
                const pos_2 = p.i;
                if (try p.parseManyPtrTypeStart()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseSliceTypeStart()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            } and try p.parsePtrMods()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseSinglePtrTypeStart() and try p.parseSinglePtrMods()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseArrayTypeStart()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePtrMods(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPtrMods);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                var i_1: usize = 0;
                while (try p.parsePtrMod()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseKEYWORD_addrspace();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and (try p.parseByteAlign() or true) and blk_1: {
                var i_1: usize = 0;
                while (try p.parsePtrMod()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and (try p.parseAddrSpace() or true) and blk_1: {
                var i_1: usize = 0;
                while (try p.parsePtrMod()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            }) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                var i_1: usize = 0;
                while (try p.parsePtrMod()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseKEYWORD_align();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and (try p.parseAddrSpace() or true) and blk_1: {
                var i_1: usize = 0;
                while (try p.parsePtrMod()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and (try p.parseByteAlign() or true) and blk_1: {
                var i_1: usize = 0;
                while (try p.parsePtrMod()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSinglePtrMods(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSinglePtrMods);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                var i_1: usize = 0;
                while (try p.parsePtrMod()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseKEYWORD_addrspace();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and (try p.parseBitAlign() or true) and blk_1: {
                var i_1: usize = 0;
                while (try p.parsePtrMod()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and (try p.parseAddrSpace() or true) and blk_1: {
                var i_1: usize = 0;
                while (try p.parsePtrMod()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            }) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                var i_1: usize = 0;
                while (try p.parsePtrMod()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseKEYWORD_align();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and (try p.parseAddrSpace() or true) and blk_1: {
                var i_1: usize = 0;
                while (try p.parsePtrMod()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and (try p.parseBitAlign() or true) and blk_1: {
                var i_1: usize = 0;
                while (try p.parsePtrMod()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePtrMod(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPtrMod);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_allowzero()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_const()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_volatile()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePrefixTypeOpPrefix(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPrefixTypeOpPrefix);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseQUESTIONMARK()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_anyframe() and try p.parseMINUSRARROW()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseLBRACKET()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseASTERISK()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSuffixOp(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSuffixOp);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseLBRACKET() and try p.parseExpr() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseDOT2() and blk_5: {
                    const pos_5 = p.i;
                    if (try p.parseExpr()) break :blk_5 true;
                    p.i = pos_5;
                    if (blk_6: {
                        const pos_6 = p.i;
                        const match_6 = try p.parseExprPrefix();
                        p.i = pos_6;
                        break :blk_6 !match_6;
                    }) break :blk_5 true;
                    p.i = pos_5;
                    break :blk_5 false;
                } and (blk_6: {
                    const pos_6 = p.i;
                    if (try p.parseCOLON() and try p.parseExpr()) break :blk_6 true;
                    p.i = pos_6;
                    break :blk_6 false;
                } or true)) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and try p.parseRBRACKET()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseDOT() and try p.parseIDENTIFIER()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseDOTASTERISK()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseDOT() and try p.parseQUESTIONMARK()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseFnCallArguments()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSuffixOpPrefix(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSuffixOpPrefix);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseLBRACKET()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseDOT() and try p.parseIDENTIFIER()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseDOTASTERISK()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseDOT() and try p.parseQUESTIONMARK()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseLPAREN()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseFnCallArguments(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defFnCallArguments);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseLPAREN() and try p.parseExprList() and try p.parseRPAREN()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSliceTypeStart(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSliceTypeStart);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseLBRACKET() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseCOLON() and try p.parseExpr()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and try p.parseRBRACKET()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSinglePtrTypeStart(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSinglePtrTypeStart);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseASTERISK()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseManyPtrTypeStart(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defManyPtrTypeStart);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseLBRACKET() and try p.parseASTERISK() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseLETTERC()) break :blk_3 true;
                p.i = pos_3;
                if (try p.parseCOLON() and try p.parseExpr()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and try p.parseRBRACKET()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseArrayTypeStart(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defArrayTypeStart);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseLBRACKET() and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseASTERISK();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parseExpr() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseCOLON() and try p.parseExpr()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and try p.parseRBRACKET()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseContainerTypeAuto(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defContainerTypeAuto);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseContainerTypeKind() and try p.parseLBRACE() and try p.parseContainerMembers() and try p.parseRBRACE()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseContainerTypeKind(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defContainerTypeKind);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_struct() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseLPAREN() and try p.parseExpr() and try p.parseRPAREN()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true)) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_opaque()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_enum() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseLPAREN() and try p.parseExpr() and try p.parseRPAREN()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true)) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_union() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseLPAREN() and blk_5: {
                    const pos_5 = p.i;
                    if (try p.parseKEYWORD_enum() and (blk_8: {
                        const pos_8 = p.i;
                        if (try p.parseLPAREN() and try p.parseExpr() and try p.parseRPAREN()) break :blk_8 true;
                        p.i = pos_8;
                        break :blk_8 false;
                    } or true)) break :blk_5 true;
                    p.i = pos_5;
                    if (try p.parseExpr()) break :blk_5 true;
                    p.i = pos_5;
                    break :blk_5 false;
                } and try p.parseRPAREN()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseByteAlign(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defByteAlign);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_align() and try p.parseLPAREN() and try p.parseExpr() and try p.parseRPAREN()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBitAlign(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBitAlign);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_align() and try p.parseLPAREN() and try p.parseExpr() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseCOLON() and try p.parseExpr() and try p.parseCOLON() and try p.parseExpr()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true) and try p.parseRPAREN()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseIdentifierList(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defIdentifierList);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((blk_3: {
                const pos_3 = p.i;
                if ((try p.parsedoc_comment() or true) and try p.parseIDENTIFIER() and (blk_6: {
                    const pos_6 = p.i;
                    if (try p.parseCOMMA() and try p.parseIdentifierList()) break :blk_6 true;
                    p.i = pos_6;
                    break :blk_6 false;
                } or true)) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSwitchProngList(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSwitchProngList);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((blk_3: {
                const pos_3 = p.i;
                if (try p.parseSwitchProng() and (blk_6: {
                    const pos_6 = p.i;
                    if (try p.parseCOMMA() and try p.parseSwitchProngList()) break :blk_6 true;
                    p.i = pos_6;
                    break :blk_6 false;
                } or true)) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAsmOutputList(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAsmOutputList);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((blk_3: {
                const pos_3 = p.i;
                if (try p.parseAsmOutputItem() and (blk_6: {
                    const pos_6 = p.i;
                    if (try p.parseCOMMA() and try p.parseAsmOutputList()) break :blk_6 true;
                    p.i = pos_6;
                    break :blk_6 false;
                } or true)) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAsmInputList(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAsmInputList);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((blk_3: {
                const pos_3 = p.i;
                if (try p.parseAsmInputItem() and (blk_6: {
                    const pos_6 = p.i;
                    if (try p.parseCOMMA() and try p.parseAsmInputList()) break :blk_6 true;
                    p.i = pos_6;
                    break :blk_6 false;
                } or true)) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseParamDeclList(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defParamDeclList);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseLPAREN() and try p.parseParamDeclListRest()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseParamDeclListRest(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defParamDeclListRest);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseRPAREN()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseDOT3() and (try p.parseCOMMA() or true) and try p.parseRPAREN()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseParamDecl() and blk_2: {
                const pos_2 = p.i;
                if (try p.parseCOMMA() and try p.parseParamDeclListRest()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseRPAREN()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseExprList(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defExprList);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseExpr() and (blk_3: {
                const pos_3 = p.i;
                if (try p.parseCOMMA() and try p.parseExprList()) break :blk_3 true;
                p.i = pos_3;
                break :blk_3 false;
            } or true)) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parseExprPrefix();
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseExprPrefix(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defExprPrefix);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseASTERISK()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsebyte_order_mark(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defbyte_order_mark);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "\xef\xbb\xbf")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsesof(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defsof);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i == 0) and (try p.parsebyte_order_mark() or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseeof(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defeof);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = blk_2: {
                    if (p.i < p.source.len) {
                        p.i += 1;
                        break :blk_2 true;
                    }
                    break :blk_2 false;
                };
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseox80_oxBF(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defox80_oxBF);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                '\x80'...'\xbf',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseoxF4(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defoxF4);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "\xf4")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseox80_ox8F(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defox80_ox8F);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                '\x80'...'\x8f',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseoxF1_oxF3(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defoxF1_oxF3);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                '\xf1'...'\xf3',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseoxF0(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defoxF0);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "\xf0")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseox90_0xBF(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defox90_0xBF);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                '\x90'...'\xbf',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseoxEE_oxEF(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defoxEE_oxEF);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                '\xee'...'\xef',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseoxED(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defoxED);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "\xed")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseox80_ox9F(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defox80_ox9F);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                '\x80'...'\x9f',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseoxE1_oxEC(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defoxE1_oxEC);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                '\xe1'...'\xec',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseoxE0(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defoxE0);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "\xe0")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseoxA0_oxBF(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defoxA0_oxBF);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                '\xa0'...'\xbf',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseoxC2_oxDF(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defoxC2_oxDF);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                '\xc2'...'\xdf',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsemultibyte_utf8(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defmultibyte_utf8);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseoxF4() and try p.parseox80_ox8F() and try p.parseox80_oxBF() and try p.parseox80_oxBF()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseoxF1_oxF3() and try p.parseox80_oxBF() and try p.parseox80_oxBF() and try p.parseox80_oxBF()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseoxF0() and try p.parseox90_0xBF() and try p.parseox80_oxBF() and try p.parseox80_oxBF()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseoxEE_oxEF() and try p.parseox80_oxBF() and try p.parseox80_oxBF()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseoxED() and try p.parseox80_ox9F() and try p.parseox80_oxBF()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseoxE1_oxEC() and try p.parseox80_oxBF() and try p.parseox80_oxBF()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseoxE0() and try p.parseoxA0_oxBF() and try p.parseox80_oxBF()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseoxC2_oxDF() and try p.parseox80_oxBF()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsenon_control_ascii(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defnon_control_ascii);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                ' '...'~',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsenon_control_utf8(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defnon_control_utf8);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                ' '...'~',
                '\x80'...'\xff',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsechar_char(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defchar_char);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "\\\\")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "\\'")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '\''...'\'',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parsenon_control_utf8()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsestring_char(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defstring_char);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "\\\\")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "\\\"")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '"'...'"',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            } and try p.parsenon_control_utf8()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsecontainer_doc_comment(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defcontainer_doc_comment);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                var match_1 = false;
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseskip() and blk_4: {
                        if (std.mem.startsWith(u8, p.source[p.i..], "//!")) {
                            p.i += 3;
                            break :blk_4 true;
                        }
                        break :blk_4 false;
                    } and blk_4: {
                        var i_4: usize = 0;
                        while (try p.parsenon_control_utf8()) {
                            if (i_4 > max_depth) return error.MaxDepth;
                            i_4 += 1;
                        }
                        break :blk_4 true;
                    } and try p.parsenewline()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    match_1 = true;
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsedoc_comment(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defdoc_comment);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_2: {
                const pos_2 = p.i;
                if (try p.parsesof()) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseskip_require_newline()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            } and blk_1: {
                var match_1 = false;
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseskip() and blk_4: {
                        if (std.mem.startsWith(u8, p.source[p.i..], "///")) {
                            p.i += 3;
                            break :blk_4 true;
                        }
                        break :blk_4 false;
                    } and blk_4: {
                        var i_4: usize = 0;
                        while (try p.parsenon_control_utf8()) {
                            if (i_4 > max_depth) return error.MaxDepth;
                            i_4 += 1;
                        }
                        break :blk_4 true;
                    } and try p.parsenewline()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    match_1 = true;
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseline_comment(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defline_comment);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "//")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '!'...'!',
                    '/'...'/',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            } and blk_1: {
                var i_1: usize = 0;
                while (try p.parsenon_control_utf8()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and try p.parsenewline()) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "////")) {
                    p.i += 4;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                var i_1: usize = 0;
                while (try p.parsenon_control_utf8()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and try p.parsenewline()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseline_string(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defline_string);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "\\\\")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                var i_1: usize = 0;
                while (try p.parsenon_control_utf8()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and try p.parsenewline()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsenewline(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defnewline);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = blk_3: {
                    const pos_3 = p.i;
                    if (blk_4: {
                        if (std.mem.startsWith(u8, p.source[p.i..], "\n")) {
                            p.i += 1;
                            break :blk_4 true;
                        }
                        break :blk_4 false;
                    }) break :blk_3 true;
                    p.i = pos_3;
                    if (blk_4: {
                        if (std.mem.startsWith(u8, p.source[p.i..], "\r\n")) {
                            p.i += 2;
                            break :blk_4 true;
                        }
                        break :blk_4 false;
                    }) break :blk_3 true;
                    p.i = pos_3;
                    if (try p.parseeof()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                };
                p.i = pos_1;
                break :blk_1 match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseskip(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defskip);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((try p.parsesof() or true) and blk_1: {
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if ((p.i < p.source.len and switch (p.source[p.i]) {
                        ' '...' ',
                        '\n'...'\n',
                        '\t'...'\t',
                        '\r'...'\r',
                        => blk_4: {
                            p.i += 1;
                            break :blk_4 true;
                        },
                        else => false,
                    })) break :blk_3 true;
                    p.i = pos_3;
                    if (try p.parseline_comment()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseskip_require_newline(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defskip_require_newline);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                var i_1: usize = 0;
                while ((p.i < p.source.len and switch (p.source[p.i]) {
                    ' '...' ',
                    '\t'...'\t',
                    '\r'...'\r',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                })) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_2: {
                const pos_2 = p.i;
                if ((p.i < p.source.len and switch (p.source[p.i]) {
                    '\n'...'\n',
                    => blk_3: {
                        p.i += 1;
                        break :blk_3 true;
                    },
                    else => false,
                })) break :blk_2 true;
                p.i = pos_2;
                if (try p.parseline_comment()) break :blk_2 true;
                p.i = pos_2;
                break :blk_2 false;
            } and try p.parseskip()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsepre_op_white(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defpre_op_white);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                var match_1 = false;
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if ((p.i < p.source.len and switch (p.source[p.i]) {
                        ' '...' ',
                        '\n'...'\n',
                        '\t'...'\t',
                        '\r'...'\r',
                        => blk_4: {
                            p.i += 1;
                            break :blk_4 true;
                        },
                        else => false,
                    })) break :blk_3 true;
                    p.i = pos_3;
                    if (try p.parseline_comment()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    match_1 = true;
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsepost_op_white(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defpost_op_white);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                ' '...' ',
                '\n'...'\n',
                '\t'...'\t',
                '\r'...'\r',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            }) and try p.parseskip()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseCHAR_LITERAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defCHAR_LITERAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and (p.i < p.source.len and switch (p.source[p.i]) {
                '\''...'\'',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            }) and blk_1: {
                var i_1: usize = 0;
                while (try p.parsechar_char()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and (p.i < p.source.len and switch (p.source[p.i]) {
                '\''...'\'',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsedigit(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defdigit);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                '_'...'_',
                '0'...'9',
                'A'...'D',
                'F'...'O',
                'Q'...'Z',
                'a'...'d',
                'f'...'o',
                'q'...'z',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsedigit_int(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defdigit_int);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsedigit()) break :blk_0 true;
            p.i = pos_0;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                'e'...'e',
                'E'...'E',
                'p'...'p',
                'P'...'P',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsedigit_float(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defdigit_float);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parsedigit()) break :blk_0 true;
            p.i = pos_0;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                'e'...'e',
                'E'...'E',
                'p'...'p',
                'P'...'P',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            }) and ((p.i < p.source.len and switch (p.source[p.i]) {
                '-'...'-',
                '+'...'+',
                => blk_2: {
                    p.i += 1;
                    break :blk_2 true;
                },
                else => false,
            }) or true)) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseNUMBERLITERAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defNUMBERLITERAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and (p.i < p.source.len and switch (p.source[p.i]) {
                '0'...'9',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            }) and blk_1: {
                var i_1: usize = 0;
                while (try p.parsedigit_int()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], ".")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                var match_1 = false;
                var i_1: usize = 0;
                while (try p.parsedigit_float()) {
                    match_1 = true;
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseskip() and (p.i < p.source.len and switch (p.source[p.i]) {
                '0'...'9',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            }) and blk_1: {
                var i_1: usize = 0;
                while (try p.parsedigit_float()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsestring(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defstring);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if ((p.i < p.source.len and switch (p.source[p.i]) {
                '"'...'"',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            }) and blk_1: {
                var i_1: usize = 0;
                while (try p.parsestring_char()) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            } and (p.i < p.source.len and switch (p.source[p.i]) {
                '"'...'"',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            })) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSTRINGLITERALSINGLE(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSTRINGLITERALSINGLE);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and try p.parsestring()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSTRINGLITERAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSTRINGLITERAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and try p.parsestring()) break :blk_0 true;
            p.i = pos_0;
            if (blk_1: {
                var match_1 = false;
                var i_1: usize = 0;
                while (blk_3: {
                    const pos_3 = p.i;
                    if (try p.parseskip() and try p.parseline_string()) break :blk_3 true;
                    p.i = pos_3;
                    break :blk_3 false;
                }) {
                    match_1 = true;
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseIDENTIFIER(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defIDENTIFIER);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                const pos_1 = p.i;
                const match_1 = try p.parsekeyword();
                p.i = pos_1;
                break :blk_1 !match_1;
            } and (p.i < p.source.len and switch (p.source[p.i]) {
                'A'...'Z',
                'a'...'z',
                '_'...'_',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            }) and blk_1: {
                var i_1: usize = 0;
                while ((p.i < p.source.len and switch (p.source[p.i]) {
                    'A'...'Z',
                    'a'...'z',
                    '0'...'9',
                    '_'...'_',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                })) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            }) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "@")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parsestring()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseBUILTINIDENTIFIER(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defBUILTINIDENTIFIER);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "@")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and (p.i < p.source.len and switch (p.source[p.i]) {
                'A'...'Z',
                'a'...'z',
                '_'...'_',
                => blk_1: {
                    p.i += 1;
                    break :blk_1 true;
                },
                else => false,
            }) and blk_1: {
                var i_1: usize = 0;
                while ((p.i < p.source.len and switch (p.source[p.i]) {
                    'A'...'Z',
                    'a'...'z',
                    '0'...'9',
                    '_'...'_',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                })) {
                    if (i_1 > max_depth) return error.MaxDepth;
                    i_1 += 1;
                }
                break :blk_1 true;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAMPERSAND(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAMPERSAND);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "&")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseAMPERSANDEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defAMPERSANDEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "&=")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseASTERISK(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defASTERISK);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "*")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '%'...'%',
                    '='...'=',
                    '|'...'|',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseASTERISKEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defASTERISKEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "*=")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseASTERISKPERCENT(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defASTERISKPERCENT);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "*%")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseASTERISKPERCENTEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defASTERISKPERCENTEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "*%=")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseASTERISKPIPE(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defASTERISKPIPE);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "*|")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseASTERISKPIPEEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defASTERISKPIPEEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "*|=")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseCARET(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defCARET);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "^")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseCARETEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defCARETEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "^=")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseCOLON(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defCOLON);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], ":")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseCOMMA(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defCOMMA);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], ",")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseDOT(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defDOT);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], ".")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '*'...'*',
                    '.'...'.',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseDOT2(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defDOT2);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "..")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '.'...'.',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseDOT3(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defDOT3);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "...")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseDOTASTERISK(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defDOTASTERISK);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], ".*")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "=")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '>'...'>',
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseEQUALEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defEQUALEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "==")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseEQUALRARROW(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defEQUALRARROW);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "=>")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseEXCLAMATIONMARK(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defEXCLAMATIONMARK);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "!")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseEXCLAMATIONMARKEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defEXCLAMATIONMARKEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "!=")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLARROW(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLARROW);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "<")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '<'...'<',
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLARROW2(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLARROW2);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "<<")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    '|'...'|',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLARROW2EQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLARROW2EQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "<<=")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLARROW2PIPE(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLARROW2PIPE);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "<<|")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLARROW2PIPEEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLARROW2PIPEEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "<<|=")) {
                    p.i += 4;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLARROWEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLARROWEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "<=")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLBRACE(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLBRACE);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "{")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLBRACKET(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLBRACKET);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "[")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLPAREN(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLPAREN);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "(")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseMINUS(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defMINUS);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "-")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '%'...'%',
                    '='...'=',
                    '>'...'>',
                    '|'...'|',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseMINUSEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defMINUSEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "-=")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseMINUSPERCENT(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defMINUSPERCENT);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "-%")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseMINUSPERCENTEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defMINUSPERCENTEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "-%=")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseMINUSPIPE(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defMINUSPIPE);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "-|")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseMINUSPIPEEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defMINUSPIPEEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "-|=")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseMINUSRARROW(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defMINUSRARROW);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "->")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePERCENT(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPERCENT);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "%")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePERCENTEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPERCENTEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "%=")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePIPE(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPIPE);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "|")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '|'...'|',
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePIPE2(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPIPE2);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "||")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePIPEEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPIPEEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "|=")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePLUS(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPLUS);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "+")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '%'...'%',
                    '+'...'+',
                    '='...'=',
                    '|'...'|',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePLUS2(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPLUS2);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "++")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePLUSEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPLUSEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "+=")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePLUSPERCENT(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPLUSPERCENT);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "+%")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePLUSPERCENTEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPLUSPERCENTEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "+%=")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePLUSPIPE(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPLUSPIPE);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "+|")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsePLUSPIPEEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defPLUSPIPEEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "+|=")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseLETTERC(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defLETTERC);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "c")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseQUESTIONMARK(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defQUESTIONMARK);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "?")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseRARROW(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defRARROW);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], ">")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '>'...'>',
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseRARROW2(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defRARROW2);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], ">>")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseRARROW2EQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defRARROW2EQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], ">>=")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseRARROWEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defRARROWEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], ">=")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseRBRACE(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defRBRACE);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "}")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseRBRACKET(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defRBRACKET);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "]")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseRPAREN(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defRPAREN);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], ")")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSEMICOLON(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSEMICOLON);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], ";")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSLASH(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSLASH);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "/")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    '='...'=',
                    '/'...'/',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseSLASHEQUAL(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defSLASHEQUAL);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "/=")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseTILDE(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defTILDE);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "~")) {
                    p.i += 1;
                    break :blk_1 true;
                }
                break :blk_1 false;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseend_of_word(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defend_of_word);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (blk_1: {
                const pos_1 = p.i;
                const match_1 = (p.i < p.source.len and switch (p.source[p.i]) {
                    'a'...'z',
                    'A'...'Z',
                    '0'...'9',
                    '_'...'_',
                    => blk_2: {
                        p.i += 1;
                        break :blk_2 true;
                    },
                    else => false,
                });
                p.i = pos_1;
                break :blk_1 !match_1;
            }) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_addrspace(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_addrspace);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "addrspace")) {
                    p.i += 9;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_align(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_align);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "align")) {
                    p.i += 5;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_allowzero(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_allowzero);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "allowzero")) {
                    p.i += 9;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_and(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_and);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "and")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_anyframe(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_anyframe);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "anyframe")) {
                    p.i += 8;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_anytype(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_anytype);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "anytype")) {
                    p.i += 7;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_asm(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_asm);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "asm")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_break(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_break);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "break")) {
                    p.i += 5;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_callconv(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_callconv);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "callconv")) {
                    p.i += 8;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_catch(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_catch);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "catch")) {
                    p.i += 5;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_comptime(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_comptime);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "comptime")) {
                    p.i += 8;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_const(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_const);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "const")) {
                    p.i += 5;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_continue(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_continue);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "continue")) {
                    p.i += 8;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_defer(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_defer);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "defer")) {
                    p.i += 5;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_else(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_else);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "else")) {
                    p.i += 4;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_enum(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_enum);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "enum")) {
                    p.i += 4;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_errdefer(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_errdefer);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "errdefer")) {
                    p.i += 8;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_error(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_error);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "error")) {
                    p.i += 5;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_export(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_export);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "export")) {
                    p.i += 6;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_extern(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_extern);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "extern")) {
                    p.i += 6;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_fn(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_fn);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "fn")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_for(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_for);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "for")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_if(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_if);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "if")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_inline(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_inline);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "inline")) {
                    p.i += 6;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_noalias(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_noalias);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "noalias")) {
                    p.i += 7;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_nosuspend(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_nosuspend);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "nosuspend")) {
                    p.i += 9;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_noinline(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_noinline);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "noinline")) {
                    p.i += 8;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_opaque(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_opaque);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "opaque")) {
                    p.i += 6;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_or(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_or);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "or")) {
                    p.i += 2;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_orelse(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_orelse);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "orelse")) {
                    p.i += 6;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_packed(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_packed);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "packed")) {
                    p.i += 6;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_pub(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_pub);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "pub")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_resume(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_resume);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "resume")) {
                    p.i += 6;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_return(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_return);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "return")) {
                    p.i += 6;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_linksection(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_linksection);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "linksection")) {
                    p.i += 11;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_struct(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_struct);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "struct")) {
                    p.i += 6;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_suspend(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_suspend);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "suspend")) {
                    p.i += 7;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_switch(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_switch);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "switch")) {
                    p.i += 6;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_test(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_test);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "test")) {
                    p.i += 4;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_threadlocal(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_threadlocal);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "threadlocal")) {
                    p.i += 11;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_try(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_try);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "try")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_union(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_union);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "union")) {
                    p.i += 5;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_unreachable(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_unreachable);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "unreachable")) {
                    p.i += 11;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_var(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_var);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "var")) {
                    p.i += 3;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_volatile(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_volatile);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "volatile")) {
                    p.i += 8;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parseKEYWORD_while(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defKEYWORD_while);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseskip() and blk_1: {
                if (std.mem.startsWith(u8, p.source[p.i..], "while")) {
                    p.i += 5;
                    break :blk_1 true;
                }
                break :blk_1 false;
            } and try p.parseend_of_word()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
    pub fn parsekeyword(p: *Parser) Error!bool {
        const def_index = @backingInt(Def.defkeyword);
        if (p.depths[def_index] > max_depth) return error.MaxDepth;
        p.depths[def_index] += 1;
        defer p.depths[def_index] -= 1;
        return blk_0: {
            const pos_0 = p.i;
            if (try p.parseKEYWORD_addrspace()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_align()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_allowzero()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_and()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_anyframe()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_anytype()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_asm()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_break()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_callconv()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_catch()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_comptime()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_const()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_continue()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_defer()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_else()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_enum()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_errdefer()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_error()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_export()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_extern()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_fn()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_for()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_if()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_inline()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_noalias()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_nosuspend()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_noinline()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_opaque()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_or()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_orelse()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_packed()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_pub()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_resume()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_return()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_linksection()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_struct()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_suspend()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_switch()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_test()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_threadlocal()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_try()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_union()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_unreachable()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_var()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_volatile()) break :blk_0 true;
            p.i = pos_0;
            if (try p.parseKEYWORD_while()) break :blk_0 true;
            p.i = pos_0;
            break :blk_0 false;
        };
    }
};
