internal struct CoroutineLibrary: LuaLibrary {
    public let name = "coroutine"

    public let create = LuaSwiftFunction {state, args in
        return [.thread(await LuaThread(in: state.thread.luaState, for: try args.checkFunction(at: 1)))]
    }

    public let resume = LuaSwiftFunction {state, args in
        do {
            var res = try await args.checkThread(at: 1).resume(in: state.thread.luaState, with: [LuaValue](args[1...]))
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

    public let running = LuaSwiftFunction {state, args in
        return [.thread(state.thread)]
    }

    public let status = LuaSwiftFunction {state, args in
        switch try args[0].checkThread(at: 1).state {
            case .suspended: return [.string(.string("suspended"))]
            case .running: return [.string(.string("running"))]
            case .normal: return [.string(.string("normal"))]
            case .dead: return [.string(.string("dead"))]
        }
    }

    public let wrap = LuaSwiftFunction {state, args in
        let coro = await LuaThread(in: state.thread.luaState, for: try args[0].checkFunction(at: 1))
        return [.function(.swift(LuaSwiftFunction {_state, _args in
            return try await coro.resume(in: _state.thread.luaState, with: _args.args)
        }))]
    }

    public let yield = LuaSwiftFunction {state, args in
        return try await LuaThread.yield(in: state.thread.luaState, with: args.args)
    }

}