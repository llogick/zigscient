export fn entry1(x: u8) void {
    switch (x) {
        1...2 => {},
        0...255 => {},
    }
}

export fn entry2(x: i8) void {
    switch (x) {
        -128...5 => {},
        5...127 => {},
    }
}

export fn entry3(x: u8) void {
    switch (x) {
        0...5 => {},
        5 => {},
        6...255 => {},
    }
}

export fn entry4(x: u8) void {
    switch (x) {
        0...5 => {},
        6 => {},
        6...255 => {},
    }
}

// error
//
// :4:10: error: duplicate switch value
// :3:10: note: previous value here
// :11:10: error: duplicate switch value
// :10:13: note: previous value here
// :17:10: error: duplicate switch value
// :18:9: note: previous value here
// :27:10: error: duplicate switch value
// :26:9: note: previous value here
