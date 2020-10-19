pub const Index2D = struct {
    x: u32,
    y: u32,
};

pub const Index3D = struct {
    x: u32,
    y: u32,
    z: u32,
};

pub fn calculate2DindexFrom1D(i: u32, count_x: u32) Index2D {
    return .{ .x = i % count_x, .y = i / count_x };
}

pub fn calculate1DindexFrom2D(index2d: Index2D, count_x: u32) u32 {
    return index2d.x + count_x * index2d.y;
}

pub fn calculate1DindexFrom3D(index3d: Index3D, count_x: u32, count_y: u32) u32 {
    return index3d.x + count_x * (index3d.y + count_y * index3d.z);
}

pub fn calculate3DindexFrom1D(i: u32, count_x: u32, count_y: u32) Index3D {
    const count_xy = count_x * count_y;
    var x = i;
    var y = i / count_x;
    var z = i / count_xy;
    x -= count_x * y;
    y -= z * count_y;
    return .{ .x = x, .y = y, .z = z };
}
