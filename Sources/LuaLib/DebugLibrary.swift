import Lua

@LuaLibrary(named: "debug")
internal final class DebugLibrary {
    public func debug(_ state: Lua) async throws {
        while true {
            if let line = readLine(), line != "cont" {
                do {
                    let cl = try await LuaLoad.load(from: line, named: "=stdin", mode: .text, environment: .table(state.luaState.globalTable), in: state)
                    _ = try await LuaFunction.lua(cl).call(in: state.thread, with: [])
                } catch let error as Lua.LuaError {
                    switch error {
                        case .luaError(let message): print(await message.toString)
                        case .runtimeError(let message): print(message)
                        case .vmError: print("vm error")
                        case .internalError: print("internal error")
                    }
                } catch LuaThread.CoroutineError.cancel {
                    throw LuaThread.CoroutineError.cancel
                } catch let error {
                    print(error.localizedDescription)
                }
            } else {
                break
            }
        }
    }

    public func gethook(_ state: Lua, thread: LuaThread?) async -> [LuaValue] {
        if let hook = await Lua(in: thread ?? state.thread).hook() {
            var mask = ""
            if hook.1.contains(.call) {mask += "c"}
            if hook.1.contains(.return) {mask += "r"}
            if hook.1.contains(.line) {mask += "l"}
            return [.function(hook.0), .string(.string(mask)), .number(Double(hook.2))]
        }
        return []
    }

    private func getinfotype(_ types: String, state: Lua) async throws -> Lua.Debug.InfoFlags {
        var retval = Lua.Debug.InfoFlags()
        let bad = types.filter {!($0 == "n" || $0 == "S" || $0 == "l" || $0 == "u" || $0 == "t" || $0 == "f" || $0 == "L")}
        if !bad.isEmpty {
            throw await Lua.error(in: state, message: "invalid option \(bad.first!)")
        }
        if types.contains("n") {retval.insert(.name)}
        if types.contains("S") {retval.insert(.source)}
        if types.contains("l") {retval.insert(.line)}
        if types.contains("u") {retval.insert(.upvalues)}
        if types.contains("t") {retval.insert(.tailCall)}
        if types.contains("f") {retval.insert(.function)}
        if types.contains("L") {retval.insert(.lines)}
        return retval
    }

    public func getinfo(_ state: Lua, _ args: LuaArgs) async throws -> LuaTable? {
        let db: Lua.Debug
        let types: Lua.Debug.InfoFlags
        if args.count >= 3 {
            // thread, f, what
            let st = Lua(in: try await args.checkThread(at: 1))
            types = try await getinfotype(try await args.checkString(at: 3), state: state)
            switch args[2] {
                case .function(let fn): db = await st.info(for: fn, with: types)
                case .number(let n):
                    if let info = await st.info(at: Int(n), with: types) {
                        db = info
                    } else {
                        return nil
                    }
                default: throw await state.argumentError(at: 2, for: args[2], expected: "function or number")
            }
        } else if args.count == 2 {
            // thread, f; or f, what
            switch args[1] {
                case .function(let fn):
                    types = try await getinfotype(try await args.checkString(at: 2), state: state)
                    db = await state.info(for: fn, with: types)
                case .number(let n):
                    types = try await getinfotype(try await args.checkString(at: 2), state: state)
                    if let info = await state.info(at: Int(n), with: types) {
                        db = info
                    } else {
                        return nil
                    }
                case .thread(let th):
                    types = .all
                    switch args[2] {
                        case .function(let fn): db = await Lua(in: th).info(for: fn)
                        case .number(let n):
                            if let info = await Lua(in: th).info(at: Int(n)) {
                                db = info
                            } else {
                                return nil
                            }
                        default: throw await state.argumentError(at: 2, for: args[2], expected: "function or number")
                    }
                default: throw await state.argumentError(at: 1, for: args[1], expected: "function or number")
            }
        } else if args.count == 1 {
            // f
            types = .all
            switch args[1] {
                case .function(let fn): db = await state.info(for: fn)
                case .number(let n):
                    if let info = await state.info(at: Int(n)) {
                        db = info
                    } else {
                        return nil
                    }
                default: throw await state.argumentError(at: 1, for: args[1], expected: "function or number")
            }
        } else {
            throw await Lua.error(in: state, message: "bad argument #1 (value expected)")
        }
        let _tab = await LuaTable(state: state)
        await _tab.isolated {tab in
            if types.contains(.name) {
                tab["name"] = db.nameWhat == .unknown ? .nil : .string(.string(db.name!))
                switch db.nameWhat! {
                    case .constant: tab["namewhat"] = .string(.string("constant"))
                    case .field: tab["namewhat"] = .string(.string("field"))
                    case .forIterator: tab["namewhat"] = .string(.string("for iterator"))
                    case .global: tab["namewhat"] = .string(.string("global"))
                    case .local: tab["namewhat"] = .string(.string("local"))
                    case .metamethod: tab["namewhat"] = .string(.string("metamethod"))
                    case .method: tab["namewhat"] = .string(.string("method"))
                    case .upvalue: tab["namewhat"] = .string(.string("upvalue"))
                    case .unknown: tab["namewhat"] = .string(.string(""))
                }
            }
            if types.contains(.source) {
                tab["source"] = .string(.string(db.source!))
                tab["short_src"] = .string(.string(db.short_src!))
                switch db.what! {
                    case .lua: tab["what"] = .string(.string("Lua"))
                    case .swift: tab["what"] = .string(.string("C"))
                    case .main: tab["what"] = .string(.string("main"))
                }
                tab["linedefined"] = .number(Double(db.lineDefined!))
                tab["lastlinedefined"] = .number(Double(db.lastLineDefined!))
            }
            if types.contains(.line) {
                tab["currentline"] = .number(Double(db.currentLine!))
            }
            if types.contains(.upvalues) {
                tab["nups"] = .number(Double(db.upvalueCount!))
                tab["nparam"] = .number(Double(db.parameterCount!))
                tab["isvararg"] = .boolean(db.isVararg!)
            }
            if types.contains(.tailCall) {
                tab["istailcall"] = .boolean(db.isTailCall!)
            }
            if types.contains(.function) {
                tab["func"] = .function(db.function!)
            }
            if types.contains(.lines) {
                if !db.validLines!.isEmpty {
                    let lines = await LuaTable(state: state)
                    await lines.isolated {_lines in
                        for k in db.validLines! {
                            _lines[k] = .boolean(true)
                        }
                    }
                    tab["activelines"] = .table(lines)
                }
            }
        }
        return _tab
    }

    public func getlocal(_ state: Lua, _ args: LuaArgs) async throws -> [LuaValue] {
        let st: Lua
        let f: LuaValue
        let local: Int
        if args.count >= 3 {
            st = Lua(in: try await args.checkThread(at: 1))
            f = args[2]
            local = try await args.checkInt(at: 3)
        } else {
            st = state
            f = args[1]
            local = try await args.checkInt(at: 2)
        }
        switch f {
            case .number(let n):
                if let v = try await st.local(at: Int(n), index: local) {
                    return [.string(.string(v.0)), v.1]
                }
            case .function(let fn):
                if let v = st.local(in: fn, index: local) {
                    return [.string(.string(v)), .nil]
                }
            default: throw await state.argumentError(at: st === state ? 1 : 2, for: f, expected: "number or function")
        }
        return []
    }

    public func getmetatable(_ state: Lua, value: LuaValue) async -> LuaTable? {
        return await value.metatable(in: state)
    }

    public func getregistry(_ state: Lua) async -> LuaTable {
        return await state.luaState.registry
    }

    public func getupvalue(_ state: Lua, f: LuaFunction, up: Int) async -> [LuaValue] {
        if let u = await state.upvalue(in: f, index: up) {
            return [.string(.string(u.0 ?? "")), u.1]
        }
        return []
    }

    public func getuservalue(value: any LuaUserdata) async -> LuaValue {
        return await value.uservalue // TODO
    }

    public func sethook(_ state: Lua, _ args: LuaArgs) async throws {
        var st = state
        var start = 1
        if case let .thread(th) = args[1] {
            st = Lua(in: th)
            start = 2
        }
        if args[start] == .nil {
            await st.hook(function: nil, for: [])
            return
        }
        let hook = try await args.checkFunction(at: start)
        let mask = try await args.checkString(at: start + 1)
        var count = 0
        var flags = Lua.HookFlags()
        if mask.contains("c") {flags.insert(.anyCall)}
        if mask.contains("r") {flags.insert(.return)}
        if mask.contains("l") {flags.insert(.line)}
        if args[start + 2] != .nil {
            count = try await args.checkInt(at: start + 2)
            flags.insert(.count)
        }
        await st.hook(function: hook, for: flags, count: count)
    }

    public func setlocal(_ state: Lua, _ args: LuaArgs) async throws -> String? {
        var st = state
        var start = 1
        if case let .thread(th) = args[1] {
            st = Lua(in: th)
            start = 2
        }
        let level = try await args.checkInt(at: start)
        let local = try await args.checkInt(at: start + 1)
        let value = args[start + 2]
        return try await st.local(at: level, index: local, value: value)
    }

    public func setmetatable(_ state: Lua, value: LuaValue, table: LuaTable?) async {
        await state.luaState.setmetatable(value: value, table: table)
    }

    public func setupvalue(_ state: Lua, function: LuaFunction, index: Int, value: LuaValue) async -> String? {
        return await state.upvalue(in: function, index: index, value: value)
    }

    public func setuservalue(ud: any LuaUserdata, value: LuaValue) async {
        await ud.set(uservalue: value)
    }

    public func traceback(_ state: Lua, _ args: LuaArgs) async throws -> LuaValue {
        var st = state
        var start = 1
        if case let .thread(th) = args[1] {
            st = Lua(in: th)
            start = 2
        }
        var retval = ""
        if args[start] != .nil {
            if case let .string(s) = args[start] {
                retval = s.string + "\n"
            } else {
                return args[start]
            }
        }
        retval += "stack traceback:\n"
        var level = try await args.checkInt(at: start + 1, default: 1)
        while true {
            if let info = await st.info(at: level, with: [.name, .source, .line]) {
                let namewhat: String
                switch info.nameWhat! {
                    case .constant: namewhat = "constant"
                    case .field: namewhat = "field"
                    case .forIterator: namewhat = "for iterator"
                    case .global: namewhat = "global"
                    case .local: namewhat = "local"
                    case .metamethod: namewhat = "metamethod"
                    case .method: namewhat = "method"
                    case .upvalue: namewhat = "upvalue"
                    case .unknown: namewhat = "function"
                }
                retval += "  \(info.short_src!):\(info.currentLine!): in \(namewhat) '\(info.name!)'\n"
            } else {
                break
            }
            level += 1
        }
        return .string(.string(retval))
    }

    public func upvalueid(_ state: Lua, function: LuaFunction, index: Int) async throws -> any LuaUserdata {
        if let uv = await state.upvalue(objectIn: function, index: index) {
            return LuaLightUserdata(for: uv)
        }
        throw await Lua.error(in: state, message: "invalid index")
    }

    public func upvaluejoin(_ state: Lua, f1: LuaFunction, n1: Int, f2: LuaFunction, n2: Int) async throws {
        try await state.upvalue(joinFrom: f1, index: n1, to: f2, index: n2)
    }
}
