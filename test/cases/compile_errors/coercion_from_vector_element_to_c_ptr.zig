export fn foo() void {
    var size: @Vector(4, c_int) = undefined;
    bar(&size[0]);
}
extern fn bar([*c]c_int) void;

// error
//
// 3:9: error: expected type '[*c]c_int', found '*align(4:0:4:0) c_int'
// 3:9: note: pointer host size '4' cannot cast into pointer host size '0'
// 5:15: note: parameter type declared here
