import Lua

public class LuaLoad {
    public enum LoadMode {
        case binary
        case text
        case any
    }

    public static func load(from source: String, named name: String?, mode: LoadMode, environment env: LuaTable) async throws -> LuaClosure {
        if source.starts(with: "\033Lua") {
            guard let res: LuaClosure = try source.withContiguousStorageIfAvailable({_chunk in
                return LuaClosure(for: try LuaInterpretedFunction(decoding: UnsafeRawBufferPointer(_chunk)), with: [LuaUpvalue(with: .table(env))], environment: env)
            }) else {throw Lua.LuaError.runtimeError(message: "could not allocate memory")}
            return res
        } else {
            var called = false
            var source = source
            if source.hasPrefix("#") {
                source = String(source[source.index(after: source.firstIndex(of: "\n") ?? source.index(before: source.endIndex))...])
            }
            return try await load(using: {if !called {called = true; return source} else {return nil}}, named: name ?? "[string '\(source[source.startIndex..<(source.index(source.startIndex, offsetBy: 30, limitedBy: source.endIndex) ?? source.endIndex)])']", mode: mode, environment: env)
        }
    }

    public static func load(using loader: @escaping () async throws -> String?, named name: String?, mode: LoadMode, environment env: LuaTable) async throws -> LuaClosure {
        // TODO: binary chunks
        let fn = try await LuaParser.parse(from: LuaLexer(using: loader, named: name ?? "?"))
        return LuaClosure(for: fn, with: [LuaUpvalue(with: .table(env))], environment: env)
    }

    public static func test() -> LuaInterpretedFunction {
        return LuaCode.test()
    }
}
