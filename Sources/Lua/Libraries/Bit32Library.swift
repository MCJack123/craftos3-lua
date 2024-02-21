internal struct Bit32Library: LuaLibrary {
    public let name = "bit32"

    public let band = LuaSwiftFunction {state, args in
        var a = UInt32(try args.checkInt(at: 1))
        _=try args.checkInt(at: 2)
        for i in 1..<args.count {
            let b = UInt32(try args.checkInt(at: i+1))
            a &= b
        }
        return [.number(Double(a))]
    }

    public let bor = LuaSwiftFunction {state, args in
        var a = UInt32(try args.checkInt(at: 1))
        _=try args.checkInt(at: 2)
        for i in 2...args.count {
            let b = UInt32(try args[i].checkInt(at: i))
            a |= b
        }
        return [.number(Double(a))]
    }

    public let bxor = LuaSwiftFunction {state, args in
        var a = UInt32(try args.checkInt(at: 1))
        _=try args.checkInt(at: 2)
        for i in 2...args.count {
            let b = UInt32(try args.checkInt(at: i))
            a ^= b
        }
        return [.number(Double(a))]
    }

    public let btest = LuaSwiftFunction {state, args in
        var a = UInt32(try args.checkInt(at: 1))
        _=try args.checkInt(at: 2)
        for i in 2...args.count {
            let b = UInt32(try args.checkInt(at: i))
            a &= b
        }
        return [.boolean(a != 0)]
    }

    public let bnot = LuaSwiftFunction {state, args in
        return [.number(Double(~UInt32(try args.checkInt(at: 1))))]
    }

    public let lshift = LuaSwiftFunction {state, args in
        return [.number(Double(UInt32(try args.checkInt(at: 1)) << (try args.checkInt(at: 2))))]
    }

    public let rshift = LuaSwiftFunction {state, args in
        return [.number(Double(UInt32(try args.checkInt(at: 1)) >> (try args.checkInt(at: 2))))]
    }

    public let arshift = LuaSwiftFunction {state, args in
        return [.number(Double(UInt32(Int32(try args.checkInt(at: 1)) >> (try args.checkInt(at: 2)))))]
    }
}