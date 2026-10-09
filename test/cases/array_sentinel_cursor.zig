fn s() usize {
    return 64;
}

fn T() type {
    return u64;
}

const Array = [64:s()]T();
const empty = [_:s()]T(){};
const items = [_:s()]T(){100};

// compile
// output_mode=Obj
