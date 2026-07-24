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

export fn entry5(x: u8) void {
    switch (x) {
        0...255 => {},
        4...120 => {},
    }
}

export fn entry6(x: u8) void {
    switch (x) {
        0...130 => {},
        120...255 => {},
    }
}

export fn entry7(x: u8) void {
    switch (x) {
        2 => {},
        0...255 => {},
    }
}

// error
//
// :4:10: error: duplicate switch ranges
// :3:10: note: overlaps with previous range here
// :3:10: note: ranges overlap from '1' to '2'
// :11:10: error: duplicate switch value '5'
// :10:13: note: previous value inside range here
// :17:10: error: duplicate switch value '5'
// :18:9: note: previous value here
// :27:10: error: duplicate switch value '6'
// :26:9: note: previous value here
// :34:10: error: duplicate switch ranges
// :33:10: note: overlaps with previous range here
// :33:10: note: ranges overlap from '4' to '120'
// :41:12: error: duplicate switch ranges
// :40:10: note: overlaps with previous range here
// :40:10: note: ranges overlap from '120' to '130'
// :48:10: error: duplicate switch value '2'
// :47:9: note: previous value here
