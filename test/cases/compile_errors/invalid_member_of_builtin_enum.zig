const lang = @import("std").lang;
export fn entry() void {
    const foo = lang.Optimize.x86;
    _ = foo;
}

// error
//
// :3:31: error: enum 'lang.Optimize' has no member named 'x86'
// : note: enum declared here
