const S = struct { x: u32 };
export fn entry1() void {
    const s = asm volatile (""
        : [_] "=r" (-> S),
    );
    _ = s;
}
export fn entry2() void {
    var s: S = undefined;
    asm volatile (""
        : [_] "=r" (s),
    );
}

const U = union { x: u32 };
export fn entry3() void {
    const u = asm volatile (""
        : [_] "=r" (-> U),
    );
    _ = u;
}
export fn entry4() void {
    var u: U = undefined;
    asm volatile (""
        : [_] "=r" (u),
    );
}
const ES = extern struct { x: u32 };
export fn entry5() void {
    var es: ES = undefined;
    asm volatile (""
        : [_] "=r" (es),
    );
}
const EU = extern union { x: u32 };
export fn entry6() void {
    var eu: EU = undefined;
    asm volatile (""
        : [_] "=r" (eu),
    );
}

// error
//
// :4:24: error: invalid inline assembly output type 'tmp.S'
// :4:24: note: struct types cannot be passed to inline assembly
// :1:11: note: struct declared here
// :11:21: error: invalid inline assembly output type 'tmp.S'
// :11:21: note: struct types cannot be passed to inline assembly
// :1:11: note: struct declared here
// :18:24: error: invalid inline assembly output type 'tmp.U'
// :18:24: note: union types cannot be passed to inline assembly
// :15:11: note: union declared here
// :25:21: error: invalid inline assembly output type 'tmp.U'
// :25:21: note: union types cannot be passed to inline assembly
// :15:11: note: union declared here
// :32:21: error: invalid inline assembly output type 'tmp.ES'
// :32:21: note: struct types cannot be passed to inline assembly
// :28:19: note: struct declared here
// :39:21: error: invalid inline assembly output type 'tmp.EU'
// :39:21: note: union types cannot be passed to inline assembly
// :35:19: note: union declared here
