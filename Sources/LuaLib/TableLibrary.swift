import Lua

internal struct TableLibrary: LuaLibrary {
    public let name = "table"

    public let concat = LuaSwiftFunction {state, args in
        let t = try await args.checkTable(at: 1)
        let sep = try await args.checkString(at: 2, default: "")
        let i = try await args.checkInt(at: 3, default: 1)
        let j = try await args.checkInt(at: 4, default: t.count)
        var res = [String]()
        for n in i...j {
            await res.append(args[n].toString)
        }
        return [.string(.string(res.joined(separator: sep)))]
    }

    public let insert = LuaSwiftFunction {state, args in
        let _t = try await args.checkTable(at: 1)
        try await _t.isolated {t in
            let pos: Int
            let val: LuaValue
            if args.count > 2 {
                pos = try await args.checkInt(at: 2)
                val = args[3]
            } else {
                pos = t.count + 1
                val = args[2]
            }
            var v = t[pos]
            var n = pos
            while v != .nil {
                let vv = t[n+1]
                t[n] = v
                v = vv
                n += 1
            }
            t[n] = v
            t[pos] = val
        }
        return []
    }

    public let pack = LuaSwiftFunction {state, args in
        let _t = await LuaTable(state: state)
        await _t.isolated {t in
            if args.count > 0 {
                for i in 1...args.count {
                    t[i] = args[i]
                }
            }
            t["n"] = .number(Double(args.count))
        }
        return [.table(_t)]
    }

    public let remove = LuaSwiftFunction {state, args in
        let _t = try await args.checkTable(at: 1)
        return try await _t.isolated {t in
            var i = try await args.checkInt(at: 2, default: t.count)
            let v = t[i]
            while t[i] != .nil {
                t[i] = t[i+1]
                i += 1
            }
            return [v]
        }
    }

    public let sort = LuaSwiftFunction {state, args in
        // TODO: add sorting function
        // guh, I need to write my own sorting algorithm for this because the comparator can yield
        let _t = try await args.checkTable(at: 1)
        var arr = await _t.isolated {t in
            var arr = [LuaValue]()
            var i = 1
            while true {
                let v = t[i]
                if v == .nil {break}
                arr.append(v)
                i += 1
            }
            return arr
        }
        try arr.sort {a, b in 
            if case let .number(an) = a, case let .number(bn) = b {
                return an < bn
            } else if case let .string(astr) = a, case let .string(bstr) = b {
                return astr.string < bstr.string
            /*} else if let mt = a.metatable(in: state), mt == b.metatable(in: state), mt["__lt"] != .nil {
                // TODO
                return false*/
            } else {
                throw Lua.LuaError.runtimeError(message: "attempt to compare two ? values")
            }
        }
        let arr_ = arr
        await _t.isolated {t in
            for (i, v) in arr_.enumerated() {
                t[i+1] = v
            }
        }
        return []
    }

    public let unpack = LuaSwiftFunction {state, args in
        let _t = try await args.checkTable(at: 1)
        let i = try await args.checkInt(at: 2, default: 1)
        return try await _t.isolated {t in
            let j = try await args.checkInt(at: 3, default: t.count)
            var res = [LuaValue]()
            if j >= i {
                for n in i...j {
                    res.append(t[n])
                }
            }
            return res
        }
    }
}