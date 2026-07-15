comptime {
    _ = 0e.0;
}
comptime {
    _ = 0E.0;
}
comptime {
    _ = 12e.0;
}
comptime {
    _ = 12E.0;
}
comptime {
    _ = 12E1.0;
}
comptime {
    _ = 0xp0;
}
comptime {
    _ = 0xP0;
}
comptime {
    _ = 0o1.0;
}

// error
//
// :2:11: error: unexpected period after exponent
// :5:11: error: unexpected period after exponent
// :8:12: error: unexpected period after exponent
// :11:12: error: unexpected period after exponent
// :14:13: error: unexpected period after exponent
// :17:9: error: expected a digit after base prefix
// :20:9: error: expected a digit after base prefix
// :23:10: error: invalid base for float literal
