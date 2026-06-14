const lang = @import("std").lang;
export fn entry() void {
    const foo = lang.OptimizeMode.x86;
    _ = foo;
}

// error
//
// :3:35: error: enum 'lang.OptimizeMode' has no member named 'x86'
// : note: enum declared here
