pub fn Handle(comptime Object: type) type {
    return packed struct {
        const Self = @This();
        pub const Index = u24;
        pub const Generation = u8;

        // usually the index into the vector of objects in the Container class
        index: Index,
        // generation, keeps track whether the handle is outdated
        generation: Generation,

        fn equal(a: Self, b: Self) bool {
            return a.index == b.index and a.generation == b.generation;
        }
    };
}
