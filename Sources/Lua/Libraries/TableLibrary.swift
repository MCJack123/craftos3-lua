internal struct TableLibrary: LuaLibrary {
    public let name = "table"

    public let concat = LuaSwiftFunction {state, args in
        let t = try args.checkTable(at: 1)
        let sep = try args.checkString(at: 2, default: "")
        let i = try args.checkInt(at: 3, default: 1)
        let j = try args.checkInt(at: 4, default: t.count)
        var res = [String]()
        for n in i...j {
            res.append(args[n].toString)
        }
        return [.string(.string(res.joined(separator: sep)))]
    }

    public let insert = LuaSwiftFunction {state, args in
        let t = try args.checkTable(at: 1)
        let pos: Int
        let val: LuaValue
        if args.count > 2 {
            pos = try args.checkInt(at: 2)
            val = args[3]
        } else {
            pos = t.count
            val = args[2]
        }
        var v = t[.number(Double(pos))]
        var n = pos
        while v != .nil {
            let vv = t[.number(Double(n+1))]
            t[.number(Double(n))] = v
            v = vv
            n += 1
        }
        t[.number(Double(n))] = v
        t[.number(Double(pos))] = val
        return []
    }

    public let pack = LuaSwiftFunction {state, args in
        let t = LuaTable()
        for i in 1...args.count {
            t[.number(Double(i))] = args[i]
        }
        t[.string(.string("n"))] = .number(Double(args.count))
        return [.table(t)]
    }



    public let unpack = LuaSwiftFunction {state, args in
        let t = try args.checkTable(at: 1)
        let i = try args.checkInt(at: 2, default: 1)
        let j = try args.checkInt(at: 3, default: t.count)
        var res = [LuaValue]()
        for n in i...j {
            res.append(t[.number(Double(n))])
        }
        return res
    }
}