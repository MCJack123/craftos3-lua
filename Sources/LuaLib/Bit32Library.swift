import Lua

internal struct Bit32Library: LuaLibrary {
    public let name = "bit32"

    public let band = LuaSwiftFunction {state, args in
        var a = UInt32(0xFFFFFFFF)
        if args.count == 0 {return [.number(Double(a))]}
        for i in 1...args.count {
            let b = UInt32(bitPattern: Int32(truncatingIfNeeded: try await args.checkInt(at: i)))
            a &= b
        }
        return [.number(Double(a))]
    }

    public let bor = LuaSwiftFunction {state, args in
        var a = UInt32(0)
        if args.count == 0 {return [.number(Double(a))]}
        for i in 1...args.count {
            let b = UInt32(bitPattern: Int32(truncatingIfNeeded: try await args.checkInt(at: i)))
            a |= b
        }
        return [.number(Double(a))]
    }

    public let bxor = LuaSwiftFunction {state, args in
        var a = UInt32(0)
        if args.count == 0 {return [.number(Double(a))]}
        for i in 1...args.count {
            let b = UInt32(bitPattern: Int32(truncatingIfNeeded: try await args.checkInt(at: i)))
            a ^= b
        }
        return [.number(Double(a))]
    }

    public let btest = LuaSwiftFunction {state, args in
        var a = UInt32(0xFFFFFFFF)
        if args.count == 0 {return [.boolean(true)]}
        for i in 1...args.count {
            let b = UInt32(bitPattern: Int32(truncatingIfNeeded: try await args.checkInt(at: i)))
            a &= b
        }
        return [.boolean(a != 0)]
    }

    public let bnot = LuaSwiftFunction {state, args in
        return [.number(Double(~UInt32(bitPattern: Int32(truncatingIfNeeded: try await args.checkInt(at: 1)))))]
    }

    public let lshift = LuaSwiftFunction {state, args in
        return [.number(Double(UInt32(bitPattern: Int32(truncatingIfNeeded: try await args.checkInt(at: 1))) << (try await args.checkInt(at: 2))))]
    }

    public let rshift = LuaSwiftFunction {state, args in
        return [.number(Double(UInt32(bitPattern: Int32(truncatingIfNeeded: try await args.checkInt(at: 1))) >> (try await args.checkInt(at: 2))))]
    }

    public let arshift = LuaSwiftFunction {state, args in
        return [.number(Double(UInt32(bitPattern: Int32(truncatingIfNeeded: try await args.checkInt(at: 1)) >> (try await args.checkInt(at: 2)))))]
    }

    public let lrotate = LuaSwiftFunction {state, args in
        let input = UInt32(bitPattern: Int32(truncatingIfNeeded: try await args.checkInt(at: 1)))
        let shift = try await args.checkInt(at: 2) & 0x1F
        return [.number(Double((input << shift) | (input >> (32 - shift))))]
    }

    public let rrotate = LuaSwiftFunction {state, args in
        let input = UInt32(bitPattern: Int32(truncatingIfNeeded: try await args.checkInt(at: 1)))
        let shift = try await args.checkInt(at: 2) & 0x1F
        return [.number(Double((input >> shift) | (input << (32 - shift))))]
    }

    public let extract = LuaSwiftFunction {state, args in
        let input = UInt32(bitPattern: Int32(truncatingIfNeeded: try await args.checkInt(at: 1)))
        let field = try await args.checkInt(at: 2)
        let width = try await args.checkInt(at: 3, default: 1)
        if field < 0 || field + width > 32 {
            throw await Lua.error(in: state, message: "trying to access non-existent bits")
        }
        return [.number(Double((input >> field) & UInt32(UInt(1 << width) - 1)))]
    }

    public let replace = LuaSwiftFunction {state, args in
        let input = UInt32(bitPattern: Int32(truncatingIfNeeded: try await args.checkInt(at: 1)))
        let value = UInt32(bitPattern: Int32(truncatingIfNeeded: try await args.checkInt(at: 2)))
        let field = try await args.checkInt(at: 3)
        let width = try await args.checkInt(at: 4, default: 1)
        if field < 0 || field + width > 32 {
            throw await Lua.error(in: state, message: "trying to access non-existent bits")
        }
        let mask = UInt32((1 << width) - 1) << field
        return [.number(Double((input & ~mask) | ((value << field) & mask)))]
    }
}