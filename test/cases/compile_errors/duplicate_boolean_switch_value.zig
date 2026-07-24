comptime {
    const x = switch (true) {
        true => false,
        false => true,
        true => false,
    };
    _ = x;
}
comptime {
    const x = switch (true) {
        false => true,
        true => false,
        false => true,
    };
    _ = x;
}

// error
//
// :5:9: error: duplicate switch value 'true'
// :3:9: note: previous value here
// :13:9: error: duplicate switch value 'false'
// :11:9: note: previous value here
