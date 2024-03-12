import Lua

@LuaLibrary(named: "debug")
internal class DebugLibrary {
    public func debug(_ state: Lua) async throws {
        while true {
            if let line = readLine(), line != "cont" {
                do {
                    let cl = try await LuaLoad.load(from: line, named: "=stdin", mode: .text, environment: .table(state.state.globalTable))
                    _ = try await LuaFunction.lua(cl).call(in: state.thread, with: [])
                } catch let error as Lua.LuaError {
                    switch error {
                        case .luaError(let message): print(message.toString)
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

    public func gethook(_ state: Lua, thread: LuaThread?) -> [LuaValue] {
        if let hook = Lua(in: thread ?? state.thread).hook() {
            var mask = ""
            if hook.1.contains(.call) {mask += "c"}
            if hook.1.contains(.return) {mask += "r"}
            if hook.1.contains(.line) {mask += "l"}
            return [.function(hook.0), .string(.string(mask)), .number(Double(hook.2))]
        }
        return []
    }

    private func getinfotype(_ types: String) -> Lua.Debug.InfoFlags {
        var retval = Lua.Debug.InfoFlags()
        if types.contains("n") {retval.insert(.name)}
        if types.contains("S") {retval.insert(.source)}
        if types.contains("l") {retval.insert(.line)}
        if types.contains("u") {retval.insert(.upvalues)}
        if types.contains("t") {retval.insert(.tailCall)}
        if types.contains("f") {retval.insert(.function)}
        if types.contains("L") {retval.insert(.lines)}
        return retval
    }

    public func getinfo(_ state: Lua, _ args: LuaArgs) throws -> LuaTable? {
        let db: Lua.Debug
        let types: Lua.Debug.InfoFlags
        if args.count >= 3 {
            // thread, f, what
            let st = Lua(in: try args.checkThread(at: 1))
            types = getinfotype(try args.checkString(at: 3))
            switch args[2] {
                case .function(let fn): db = st.info(for: fn, with: types)
                case .number(let n):
                    if let info = st.info(at: Int(n), with: types) {
                        db = info
                    } else {
                        return nil
                    }
                default: throw state.argumentError(at: 2, for: args[2], expected: "function or number")
            }
        } else if args.count == 2 {
            // thread, f; or f, what
            switch args[1] {
                case .function(let fn):
                    types = getinfotype(try args.checkString(at: 2))
                    db = state.info(for: fn, with: types)
                case .number(let n):
                    types = getinfotype(try args.checkString(at: 2))
                    if let info = state.info(at: Int(n), with: types) {
                        db = info
                    } else {
                        return nil
                    }
                case .thread(let th):
                    types = .all
                    switch args[2] {
                        case .function(let fn): db = Lua(in: th).info(for: fn)
                        case .number(let n):
                            if let info = Lua(in: th).info(at: Int(n)) {
                                db = info
                            } else {
                                return nil
                            }
                        default: throw state.argumentError(at: 2, for: args[2], expected: "function or number")
                    }
                default: throw state.argumentError(at: 1, for: args[1], expected: "function or number")
            }
        } else if args.count == 1 {
            // f
            types = .all
            switch args[1] {
                case .function(let fn): db = state.info(for: fn)
                case .number(let n):
                    if let info = state.info(at: Int(n)) {
                        db = info
                    } else {
                        return nil
                    }
                default: throw state.argumentError(at: 1, for: args[1], expected: "function or number")
            }
        } else {
            throw Lua.error(in: state, message: "bad argument #1 (value expected)")
        }
        let tab = LuaTable(state: state)
        if types.contains(.name) {
            tab["name"] = .string(.string(db.name!))
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
            let lines = LuaTable(state: state)
            for k in db.validLines! {
                lines[.number(Double(k))] = .boolean(true)
            }
            tab["activelines"] = .table(lines)
        }
        return tab
    }

    public func getlocal(_ state: Lua, _ args: LuaArgs) throws -> [LuaValue] {
        let st: Lua
        let f: LuaValue
        let local: Int
        if args.count >= 3 {
            st = Lua(in: try args.checkThread(at: 1))
            f = args[2]
            local = try args.checkInt(at: 3)
        } else {
            st = state
            f = args[1]
            local = try args.checkInt(at: 2)
        }
        switch f {
            case .number(let n):
                if let v = try st.local(at: Int(n), index: local) {
                    return [.string(.string(v.0)), v.1]
                }
            case .function(let fn):
                if let v = st.local(in: fn, index: local) {
                    return [.string(.string(v)), .nil]
                }
            default: throw state.argumentError(at: st === state ? 1 : 2, for: f, expected: "number or function")
        }
        return []
    }

    public func getmetatable(_ state: Lua, value: LuaValue) -> LuaTable? {
        return value.metatable(in: state)
    }

    public func getregistry(_ state: Lua) -> LuaTable {
        return state.state.registry
    }

    public func getupvalue(_ state: Lua, f: LuaFunction, up: Int) -> [LuaValue] {
        if let u = state.upvalue(in: f, index: up) {
            return [.string(.string(u.0 ?? "")), u.1]
        }
        return []
    }

    public func getuservalue(value: LuaUserdata) -> LuaValue {
        return value.uservalue // TODO
    }

    public func sethook(_ state: Lua, _ args: LuaArgs) throws {
        var st = state
        var start = 1
        if case let .thread(th) = args[1] {
            st = Lua(in: th)
            start = 2
        }
        if args[start] == .nil {
            st.hook(function: nil, for: [])
            return
        }
        let hook = try args.checkFunction(at: start)
        let mask = try args.checkString(at: start + 1)
        var count = 0
        var flags = Lua.HookFlags()
        if mask.contains("c") {flags.insert(.anyCall)}
        if mask.contains("r") {flags.insert(.return)}
        if mask.contains("l") {flags.insert(.line)}
        if args[start + 2] != .nil {
            count = try args.checkInt(at: start + 2)
            flags.insert(.count)
        }
        st.hook(function: hook, for: flags, count: count)
    }

    public func setlocal(_ state: Lua, _ args: LuaArgs) throws -> String? {
        var st = state
        var start = 1
        if case let .thread(th) = args[1] {
            st = Lua(in: th)
            start = 2
        }
        let level = try args.checkInt(at: start)
        let local = try args.checkInt(at: start + 1)
        let value = args[start + 2]
        return try st.local(at: level, index: local, value: value)
    }

    public func setmetatable(_ state: Lua, value: LuaValue, table: LuaTable?) {
        switch value {
            case .table(let t): t.metatable = table
            case .userdata(let t): t.metatable = table
            case .nil: state.state.nilMetatable = table
            case .boolean: state.state.booleanMetatable = table
            case .number: state.state.numberMetatable = table
            case .string: state.state.stringMetatable = table
            case .function: state.state.functionMetatable = table
            case .thread: state.state.threadMetatable = table
        }
    }

    public func setupvalue(_ state: Lua, function: LuaFunction, index: Int, value: LuaValue) -> String? {
        return state.upvalue(in: function, index: index, value: value)
    }

    public func setuservalue(ud: LuaUserdata, value: LuaValue) {
        ud.uservalue = value
    }

    public func traceback(_ state: Lua, _ args: LuaArgs) throws -> LuaValue {
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
        var level = try args.checkInt(at: start + 1, default: 1)
        while true {
            if let info = st.info(at: level, with: [.name, .source, .line]) {
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
                retval += "  \(info.source!.string):\(info.currentLine!): in \(namewhat) '\(info.name!)'\n"
            } else {
                break
            }
            level += 1
        }
        return .string(.string(retval))
    }

    public func upvalueid(_ state: Lua, function: LuaFunction, index: Int) throws -> LuaUserdata {
        if let uv = state.upvalue(objectIn: function, index: index) {
            return LuaUserdata(for: uv)
        }
        throw Lua.error(in: state, message: "invalid index")
    }

    public func upvaluejoin(_ state: Lua, f1: LuaFunction, n1: Int, f2: LuaFunction, n2: Int) throws {
        try state.upvalue(joinFrom: f1, index: n1, to: f2, index: n2)
    }
}
