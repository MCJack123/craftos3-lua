import Lua

internal extension String {
    var trimmingSpaces: Substring {
        var index = startIndex
        while index < endIndex && self[index].isWhitespace {
            index = self.index(after: index)
        }
        if index == endIndex {
            return Substring()
        }
        var eindex = self.index(before: endIndex)
        while eindex > index && self[eindex].isWhitespace {
            eindex = self.index(before: eindex)
        }
        return self[index...eindex]
    }
}

// https://www.swiftbysundell.com/articles/async-and-concurrent-forEach-and-map/
internal extension Sequence {
    func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        var values = [T]()

        for element in self {
            try await values.append(transform(element))
        }

        return values
    }

    func asyncMap<T>(
        _ transform: (Element) async -> T
    ) async -> [T] {
        var values = [T]()

        for element in self {
            await values.append(transform(element))
        }

        return values
    }
}

internal extension Sequence where Element: Sendable {
    func concurrentMap<T: Sendable>(
        _ transform: @Sendable @escaping (Element) async throws -> T
    ) async throws -> [T] {
        let tasks = map { element in
            Task {
                try await transform(element)
            }
        }

        return try await tasks.asyncMap { task in
            try await task.value
        }
    }

    func concurrentMap<T: Sendable>(
        _ transform: @Sendable @escaping (Element) async -> T
    ) async -> [T] {
        let tasks = map { element in
            Task {
                await transform(element)
            }
        }

        return await tasks.asyncMap { task in
            await task.value
        }
    }
}

internal struct BaseLibrary: LuaLibrary {
    public let name = "base"

    public let _VERSION = LuaValue.string(.string("Lua 5.2"))

    public let assert = LuaSwiftFunction {state, args in
        if !args[1].toBool {
            var msg = args[2].orElse(.string(.string("assertion failed!")))
            if case let .table(debug) = await state.global(named: "debug"), case let .function(traceback) = await debug["traceback"] {
                msg = try await traceback.call(in: state.thread, with: [msg])[0]
            }
            if case let .string(s) = msg {
                throw await Lua.error(in: state, message: s.string)
            }
            throw Lua.LuaError.luaError(message: msg)
        }
        return args.args
    }

    public let error = LuaSwiftFunction {state, args in
        if case let .string(s) = args[1] {
            throw await Lua.error(in: state, message: s.string, at: try await args.checkInt(at: 2, default: 1))
        }
        throw Lua.LuaError.luaError(message: args[1])
    }

    public let getmetatable = LuaSwiftFunction {state, args in
        if case let .table(tab) = args[1] {
            if let mt = await tab.metatable {
                let mmt = await mt["__metatable"]
                if mmt != .nil {
                    return [mmt]
                }
                return [.table(mt)]
            } else {
                return [.nil]
            }
        } else if let mt = await args[1].metatable(in: state) {
            return [.table(mt)]
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
        throw await state.argumentError(at: 1, in: args, expected: "table")
    }

    public let load = LuaSwiftFunction {state, args in
        switch args[1] {
            case .string, .function: break
            default: throw await state.argumentError(at: 1, in: args, expected: "string or function")
        }
        let name = args[2] != .nil ? try await args.checkBytes(at: 2) : nil
        let modestr = try await args.checkString(at: 3, default: "bt")
        let mode: LuaLoad.LoadMode
        switch modestr {
            case "b": mode = .binary
            case "t": mode = .text
            case "bt", "tb": mode = .any
            default: throw await Lua.error(in: state, message: "bad argument #3 (invalid mode)")
        }
        do {
            switch args[1] {
                case .string(let chunk): return [.function(.lua(try await LuaLoad.load(from: chunk.bytes, named: name, mode: mode, environment: args[4].orElse(.table(state.luaState.globalTable)))))]
                case .function(let fn): return [.function(.lua(try await LuaLoad.load(using: {() -> [UInt8]? in
                        guard let v = try await fn.call(in: state.thread, with: []).first?.optional else {return nil}
                        guard case let .string(s) = v else {throw Lua.LuaError.runtimeError(message: "reader function must return a string")}
                        if s.string == "" {return nil}
                        return s.bytes
                    }, named: name, mode: mode, environment: args[4].orElse(.table(state.luaState.globalTable)))))]
                default: Swift.assert(false); return [] // should never happen
            }
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
                default:
                    throw error
            }
        } catch let error as LuaInterpretedFunction.DecodeError {
            switch error {
                case .invalidBytecode:
                    return [.nil, .string(.string("invalid bytecode"))]
            }
        } catch LuaThread.CoroutineError.cancel {
            throw LuaThread.CoroutineError.cancel
        } catch let error {
            return [.nil, .string(.string(error.localizedDescription))]
        }
    }

    public let next = LuaSwiftFunction {state, args in
        let tab = try await args.checkTable(at: 1)
        let k = await tab.next(key: args[2])
        if k == .nil {
            return []
        }
        return [k, await tab[k]]
    }

    public var pairs: LuaSwiftFunction = LuaSwiftFunction {state, args in []} // temporary
    @Sendable private func _pairs(_ state: Lua, _ args: LuaArgs) async throws -> [LuaValue] {
        let tab = try await args.checkTable(at: 1)
        if let mt = await tab.metatable?["__pairs"], case let .function(fn) = mt {
            return try await fn.call(in: state.thread, with: [.table(tab)])
        }
        return [
            .function(.swift(self.next)),
            .table(tab),
            .nil
        ]
    }

    public let pcall = LuaSwiftFunction {state, args in
        let fn = try await args.checkFunction(at: 1)
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
        } catch LuaThread.CoroutineError.cancel {
            throw LuaThread.CoroutineError.cancel
        } catch {
            return [.boolean(false), .string(.string(String(describing: error)))]
        }
    }

    public let print = LuaSwiftFunction {state, args in
        Swift.print(await args.args.concurrentMap {await $0.toString}.joined(separator: "\t"))
        return []
    }

    public let rawequal = LuaSwiftFunction {state, args in
        return [.boolean(args[1] == args[2])]
    }

    public let rawget = LuaSwiftFunction {state, args in
        let tab = try await args.checkTable(at: 1)
        return [await tab[args[2]]]
    }

    public let rawlen = LuaSwiftFunction {state, args in
        switch args[1] {
            case .string(let str): return [.number(Double(str.string.count))]
            case .table(let tab): return [.number(Double(await tab.count))]
            default: throw await state.argumentError(at: 1, in: args, expected: "table or string")
        }
    }

    public let rawset = LuaSwiftFunction {state, args in
        let tab = try await args.checkTable(at: 1)
        await tab.set(index: args[2], value: args[3])
        return []
    }

    public let select = LuaSwiftFunction {state, args in
        if args[1] == .string(.string("#")) {
            return [.number(Double(args.count - 1))]
        }
        let idx = Int(try await args.checkNumber(at: 1)) + 1
        if idx <= 0 {
            return [LuaValue](args[(args.count+idx)...])
        }
        return [LuaValue](args[idx...])
    }

    public let setmetatable = LuaSwiftFunction {state, args in
        let tab = try await args.checkTable(at: 1)
        switch args[2] {
            case .nil: await tab.set(metatable: nil)
            case .table(let mt):
                if let curmt = await tab.metatable {
                    if await curmt["__metatable"] != .nil {
                        throw await Lua.error(in: state, message: "cannot set metatable")
                    }
                }
                await tab.set(metatable: mt)
            default: throw await state.argumentError(at: 2, in: args, expected: "table")
        }
        return [.table(tab)]
    }

    public let tonumber = LuaSwiftFunction {state, args in
        if args.count < 1 {
            throw await Lua.error(in: state, message: "bad argument #1 (value expected)")
        }
        switch args[1] {
            case .number: return [args[1]]
            case .string(let s):
                if s.string.lowercased() == "nan" || s.string.lowercased() == "inf" || s.string.contains("\0") {
                    // special case
                    return [.nil]
                }
                if args[2] != .nil {
                    let radix = Int(try await args.checkNumber(at: 2))
                    if let n = Int(s.string.trimmingSpaces, radix: radix) {
                        return [.number(Double(n))]
                    } else {
                        return [.nil]
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
            throw await Lua.error(in: state, message: "bad argument #1 (value expected)")
        }
        if let mt = await args[1].metatable(in: state)?["__tostring"], case let .function(fn) = mt {
            let vals = try await fn.call(in: state.thread, with: [args[1]])
            return [vals.first ?? .nil]
        }
        return [.string(.string(await args[1].toString))]
    }

    public let type = LuaSwiftFunction {state, args in
        return [.string(.string(args[1].type))]
    }

    public let xpcall = LuaSwiftFunction {state, args in
        let fn = try await args.checkFunction(at: 1)
        let err = try await args.checkFunction(at: 2)
        do {
            var res = try await fn.pcall(in: state.thread, with: [LuaValue](args[3...]), handler: {error in
                let message: LuaValue
                if let error = error as? Lua.LuaError {
                    switch error {
                        case .luaError(let msg): message = msg
                        case .runtimeError(let msg): message = .string(.string(msg))
                        default: message = .string(.string("Internal VM error"))
                    }
                } else {
                    message = .string(.string(error.localizedDescription))
                }
                return try await err.call(in: state.thread, with: [message]).first ?? .nil
            })
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
            } catch LuaThread.CoroutineError.cancel {
                throw LuaThread.CoroutineError.cancel
            } catch {
                return [.boolean(false), .string(.string("error in error handling"))]
            }
        } catch LuaThread.CoroutineError.cancel {
            throw LuaThread.CoroutineError.cancel
        } catch {
            let errmsg = LuaValue.string(.string(String(describing: error)))
            do {
                var res = try await err.call(in: state.thread, with: [errmsg])
                res.insert(.boolean(false), at: 0)
                return res
            } catch LuaThread.CoroutineError.cancel {
                throw LuaThread.CoroutineError.cancel
            } catch {
                return [.boolean(false), .string(.string("error in error handling"))]
            }
        }
    }

    public init() {
        pairs = LuaSwiftFunction(from: self._pairs)
    }
}