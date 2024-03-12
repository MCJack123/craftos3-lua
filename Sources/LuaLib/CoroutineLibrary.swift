import Lua

internal struct CoroutineLibrary: LuaLibrary {
    public let name = "coroutine"

    public let create = LuaSwiftFunction {state, args in
        return [.thread(await LuaThread(in: state, for: try args.checkFunction(at: 1)))]
    }

    public let resume = LuaSwiftFunction {state, args in
        let th = try args.checkThread(at: 1)
        do {
            var res = try await th.resume(in: state, with: [LuaValue](args[2...]))
            res.insert(.boolean(true), at: 0)
            return res
        } catch let error as Lua.LuaError {
            switch error {
                case .luaError(let msg): return [.boolean(false), msg]
                case .runtimeError(let msg): return [.boolean(false), .string(.string(msg))]
                default: return [.boolean(false), .string(.string("Internal VM error"))]
            }
        } catch let error as LuaThread.CoroutineError {
            switch error {
                case .cancel:
                    throw LuaThread.CoroutineError.cancel
                case .noCoroutine:
                    return [.boolean(false), .string(.string("no coroutine"))] // this should never happen
                case .notSuspended:
                    return [.boolean(false), .string(.string("cannot resume a \(String(describing: th.state)) coroutine"))]
            }
        } catch {
            return [.boolean(false), .string(.string(String(describing: error)))]
        }
    }

    public let running = LuaSwiftFunction {state, args in
        return [.thread(state.thread), .boolean(state.thread.state == .dead)]
    }

    public let status = LuaSwiftFunction {state, args in
        return [.string(.string(String(describing: try args.checkThread(at: 1).state)))]
    }

    public let wrap = LuaSwiftFunction {state, args in
        let coro = await LuaThread(in: state, for: try args.checkFunction(at: 1))
        return [.function(.swift(LuaSwiftFunction {_state, _args in
            return try await coro.resume(in: _state, with: _args.args)
        }))]
    }

    public let yield = LuaSwiftFunction {state, args in
        return try await LuaThread.yield(in: state, with: args.args)
    }
}
