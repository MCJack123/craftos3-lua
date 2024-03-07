import Lua

internal struct BaseLibrary: LuaLibrary {
    public let name = "base"

    public let _VERSION = LuaValue.string(.string("Lua 5.2"))

    public let assert = LuaSwiftFunction {state, args in
        if !args[1].toBool {
            let msg = args[2].orElse(.string(.string("assertion failed!")))
            if case let .string(s) = msg {
                throw Lua.error(in: state, message: s.string)
            }
            throw Lua.LuaError.luaError(message: msg)
        }
        return [args[1]]
    }

    public let error = LuaSwiftFunction {state, args in
        if case let .string(s) = args[1] {
            throw Lua.error(in: state, message: s.string, at: try args.checkInt(at: 2, default: 1))
        }
        throw Lua.LuaError.luaError(message: args[1])
    }

    public let getmetatable = LuaSwiftFunction {state, args in
        if case let .table(tab) = args[1] {
            if let mt = tab.metatable {
                let mmt = mt["__metatable"]
                if mmt != .nil {
                    return [mmt]
                }
                return [.table(mt)]
            } else {
                return [.nil]
            }
        }
        return [.nil]
    }

    public let ipairs = LuaSwiftFunction {state, args in
        if case let .table(tab) = args[1] {
            return [
                .function(.swift(LuaSwiftFunction {_state, _args in
                    if case let .number(i) = _args[2] {
                        let v = try await args[1].index(.number(i+1), in: _state)
                        if v == .nil {
                            return []
                        }
                        return [.number(i+1), v]
                    } else {
                        return []
                    }
                })),
                .table(tab),
                .number(0)
            ]
        }
        throw Lua.argumentError(at: 1, in: args, expected: "table")
    }

    public let load = LuaSwiftFunction {state, args in
        let chunk = try args.checkString(at: 1)
        let name = args[2] != .nil ? try args.checkString(at: 2) : nil
        let modestr = try args.checkString(at: 3, default: "bt")
        let env = try args.checkTable(at: 4, default: state.state.globalTable)
        let mode: LuaLoad.LoadMode
        switch modestr {
            case "b": mode = .binary
            case "t": mode = .text
            case "bt", "tb": mode = .any
            default: throw Lua.error(in: state, message: "bad argument #3 (invalid mode)")
        }
        do {
            return [.function(.lua(try await LuaLoad.load(from: chunk, named: name, mode: mode, environment: env)))]
        } catch let error as LuaParser.Error {
            switch error {
                case .syntaxError(let message, let token):
                    return [.nil, .string(.string("\(name ?? "?"):\(token?.line ?? 0): \(message) near '\(token?.text ?? "<eof>")'"))]
                case .gotoError(let message):
                    return [.nil, .string(.string(message))]
                case .codeError(let message):
                    return [.nil, .string(.string(message))]
            }
        } catch let error as Lua.LuaError {
            switch error {
                case .runtimeError(let message):
                    return [.nil, .string(.string(message))]
                case .luaError(let message):
                    return [.nil, message]
                case .vmError:
                    return [.nil, .string(.string("vm error"))]
                default:
                    return [.nil, .string(.string(error.localizedDescription))]
            }
        } catch let error {
            return [.nil, .string(.string(error.localizedDescription))]
        }
    }

    public let next = LuaSwiftFunction {state, args in
        let tab = try args.checkTable(at: 1)
        let k = tab.next(key: args[2])
        if k == .nil {
            return []
        }
        return [k, tab[k]]
    }

    public var pairs: LuaSwiftFunction = LuaSwiftFunction {state, args in []} // temporary
    private func _pairs(_ state: Lua, _ args: LuaArgs) async throws -> [LuaValue] {
        let tab = try args.checkTable(at: 1)
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
        let fn = try args.checkFunction(at: 1)
        do {
            var res = try await fn.call(in: state.thread, with: [LuaValue](args[2...]))
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
        Swift.print(args.args.map {$0.toString}.joined(separator: "\t"))
        return []
    }

    public let rawequal = LuaSwiftFunction {state, args in
        return [.boolean(args[1] == args[2])]
    }

    public let rawget = LuaSwiftFunction {state, args in
        let tab = try args.checkTable(at: 1)
        return [tab[args[2]]]
    }

    public let rawlen = LuaSwiftFunction {state, args in
        switch args[1] {
            case .string(let str): return [.number(Double(str.string.count))]
            case .table(let tab): return [.number(Double(tab.count))]
            default: throw Lua.argumentError(at: 1, in: args, expected: "table or string")
        }
    }

    public let rawset = LuaSwiftFunction {state, args in
        let tab = try args.checkTable(at: 1)
        tab[args[2]] = args[3]
        return []
    }

    public let select = LuaSwiftFunction {state, args in
        if args[1] == .string(.string("#")) {
            return [.number(Double(args.count))]
        }
        let idx = Int(try args.checkNumber(at: 1))
        return [LuaValue](args[idx...])
    }

    public let setmetatable = LuaSwiftFunction {state, args in
        let tab = try args.checkTable(at: 1)
        switch args[2] {
            case .nil: tab.metatable = nil
            case .table(let mt):
                if let curmt = tab.metatable {
                    if curmt["__metatable"] != .nil {
                        throw Lua.error(in: state, message: "cannot set metatable")
                    }
                }
                tab.metatable = mt
            default: throw Lua.argumentError(at: 2, in: args, expected: "table")
        }
        return [.table(tab)]
    }

    public let tonumber = LuaSwiftFunction {state, args in
        if args.count < 1 {
            throw Lua.error(in: state, message: "bad argument #1 (value expected)")
        }
        switch args[1] {
            case .number: return [args[1]]
            case .string(let s):
                if args[2] != .nil {
                    let radix = Int(try args.checkNumber(at: 2))
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
        if args.count < 1 {
            throw Lua.error(in: state, message: "bad argument #1 (value expected)")
        }
        if let mt = args[1].metatable(in: state)?["__tostring"], case let .function(fn) = mt {
            let vals = try await fn.call(in: state.thread, with: [args[1]])
            return [vals.first ?? .nil]
        }
        return [.string(.string(args[1].toString))]
    }

    public let type = LuaSwiftFunction {state, args in
        return [.string(.string(args[1].type))]
    }

    public let xpcall = LuaSwiftFunction {state, args in
        let fn = try args.checkFunction(at: 1)
        let err = try args.checkFunction(at: 2)
        do {
            var res = try await fn.call(in: state.thread, with: [LuaValue](args[3...]))
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