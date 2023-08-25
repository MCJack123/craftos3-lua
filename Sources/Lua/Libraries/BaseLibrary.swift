internal struct BaseLibrary: LuaLibrary {
    public let name = "base"

    public let assert = LuaSwiftFunction {state, args in
        if !args[safe: 0].toBool {
            throw Lua.LuaError.luaError(message: args[safe: 1].orElse(.string(.string("assertion failed!"))))
        }
        return [args[safe: 0]]
    }

    public let error = LuaSwiftFunction {state, args in
        // TODO: insert level
        throw Lua.LuaError.luaError(message: args[safe: 0])
    }

    public let getmetatable = LuaSwiftFunction {state, args in
        if case let .table(tab) = args[safe: 0] {
            if let mt = tab.metatable {
                return [.table(mt)]
            } else {
                return [.nil]
            }
        }
        throw Lua.argumentError(at: 1, in: args, expected: "table")
    }

    public let ipairs = LuaSwiftFunction {state, args in
        if case let .table(tab) = args[safe: 0] {
            return [
                .function(.swift(LuaSwiftFunction {_state, _args in
                    if case let .number(i) = _args[safe: 1], let v = tab.members[.number(i+1)] {
                        return [.number(i+1), v]
                    } else {
                        return [.nil]
                    }
                })),
                .table(tab),
                .number(0)
            ]
        }
        throw Lua.argumentError(at: 1, in: args, expected: "table")
    }

    public let load = LuaSwiftFunction {state, args in
        let chunk = try args[safe: 0].checkString(at: 1)
        let defaultEnv: LuaTable
        switch state.thread.callStack.last!.function {
            case .lua(let cl): defaultEnv = cl.environment
            case .swift: defaultEnv = LuaTable()
        }
        let env = try args[safe: 3].checkTable(at: 4, default: defaultEnv)
        return try chunk.withContiguousStorageIfAvailable {_chunk in
            return [LuaValue.function(.lua(LuaClosure(for: try LuaInterpretedFunction(decoding: UnsafeRawBufferPointer(_chunk)), with: [], environment: env)))]
        } ?? []
    }

    public let next = LuaSwiftFunction {state, args in
        let tab = try args[safe: 0].checkTable(at: 1)
        if args[safe: 1] == .nil {
            guard let entry = tab.members.first else {return [.nil]}
            return [entry.key, entry.value]
        } else if let index = tab.members.index(forKey: args[safe: 1]) {
            let entry = tab.members[tab.members.index(after: index)]
            return [entry.key, entry.value]
        } else {
            return [.nil]
        }
    }

    public var pairs: LuaSwiftFunction = LuaSwiftFunction {state, args in []} // temporary
    private func _pairs(_ state: Lua, _ args: [LuaValue]) async throws -> [LuaValue] {
        let tab = try args[safe: 0].checkTable(at: 1)
        if let mt = tab.metatable?["__pairs"], case let .function(fn) = mt {
            return try await fn.call(in: state.thread, with: [.table(tab)])
        }
        return [
            .function(.swift(self.next)),
            .table(tab),
            .nil
        ]
    }

    public let pcall = LuaSwiftFunction {state, args in
        let fn = try args[safe: 0].checkFunction(at: 1)
        do {
            var res = try await fn.call(in: state.thread, with: [LuaValue](args[1...]))
            res.insert(.boolean(true), at: 0)
            return res
        } catch let error as Lua.LuaError {
            switch error {
                case .luaError(let msg): return [.boolean(false), msg]
                case .runtimeError(let msg): return [.boolean(false), .string(.string(msg))]
                default: return [.boolean(false), .string(.string("Internal VM error"))]
            }
        } catch {
            return [.boolean(false), .string(.string(String(describing: error)))]
        }
    }

    public let print = LuaSwiftFunction {state, args in
        Swift.print(args.map {$0.toString}.joined(separator: "\t"))
        return []
    }

    public let rawequal = LuaSwiftFunction {state, args in
        return [.boolean(args[safe: 0] == args[safe: 1])]
    }

    public let rawget = LuaSwiftFunction {state, args in
        let tab = try args[safe: 0].checkTable(at: 1)
        return [tab.members[args[safe: 1]] ?? .nil]
    }

    public let rawlen = LuaSwiftFunction {state, args in
        switch args[safe: 0] {
            case .string(let str): return [.number(Double(str.string.count))]
            case .table(let tab): return [.number(Double(tab.count))]
            default: throw Lua.argumentError(at: 1, in: args, expected: "table or string")
        }
    }

    public let rawset = LuaSwiftFunction {state, args in
        let tab = try args[safe: 0].checkTable(at: 1)
        tab.members[args[safe: 1]] = args[safe: 2] == .nil ? nil : args[safe: 2]
        return []
    }

    public let select = LuaSwiftFunction {state, args in
        if args[safe: 0] == .string(.string("#")) {
            return [.number(Double(args.count))]
        }
        let idx = Int(try args[safe: 0].checkNumber(at: 1))
        return [LuaValue](args[idx...])
    }

    public let setmetatable = LuaSwiftFunction {state, args in
        let tab = try args[safe: 0].checkTable(at: 1)
        switch args[safe: 1] {
            case .nil: tab.metatable = nil
            case .table(let mt): tab.metatable = mt
            default: throw Lua.argumentError(at: 2, in: args, expected: "table")
        }
        return []
    }

    public let tonumber = LuaSwiftFunction {state, args in
        switch args[safe: 0] {
            case .number: return [args[safe: 0]]
            case .string(let s):
                if args[safe: 1] != .nil {
                    let radix = Int(try args[safe: 1].checkNumber(at: 2))
                    if let n = Int(s.string, radix: radix) {
                        return [.number(Double(n))]
                    }
                }
                if let n = Double(s.string) {
                    return [.number(n)]
                } else {
                    return [.nil]
                }
            default: return [.nil]
        }
    }

    public let tostring = LuaSwiftFunction {state, args in
        if let mt = args[safe: 0].metatable(in: state.thread.luaState)?["__tostring"], case let .function(fn) = mt {
            return try await fn.call(in: state.thread, with: args)
        }
        return [.string(.string(args[safe: 0].toString))]
    }

    public let type = LuaSwiftFunction {state, args in
        return [.string(.string(args[safe: 0].type))]
    }

    public let xpcall = LuaSwiftFunction {state, args in
        let fn = try args[safe: 0].checkFunction(at: 1)
        let err = try args[safe: 1].checkFunction(at: 2)
        do {
            var res = try await fn.call(in: state.thread, with: [LuaValue](args[2...]))
            res.insert(.boolean(true), at: 0)
            return res
        } catch let error as Lua.LuaError {
            let errmsg: LuaValue
            switch error {
                case .luaError(let msg): errmsg = msg
                case .runtimeError(let msg): errmsg = .string(.string(msg))
                default: errmsg = .string(.string("Internal VM error"))
            }
            do {
                var res = try await err.call(in: state.thread, with: [errmsg])
                res.insert(.boolean(false), at: 0)
                return res
            } catch {
                return [.boolean(false), .string(.string("error in error handling"))]
            }
        } catch {
            let errmsg = LuaValue.string(.string(String(describing: error)))
            do {
                var res = try await err.call(in: state.thread, with: [errmsg])
                res.insert(.boolean(false), at: 0)
                return res
            } catch {
                return [.boolean(false), .string(.string("error in error handling"))]
            }
        }
    }

    public init() {
        pairs = LuaSwiftFunction(from: self._pairs)
    }
}