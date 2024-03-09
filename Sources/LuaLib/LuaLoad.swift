import Lua

public class LuaLoad {
    public enum LoadMode {
        case binary
        case text
        case any
    }

    public static func load(from source: String, named name: String?, mode: LoadMode, environment env: LuaTable) async throws -> LuaClosure {
        if source.starts(with: "\u{1b}Lua") {
            if mode != .binary && mode != .any {
                throw Lua.LuaError.runtimeError(message: "attempt to load a binary chunk")
            }
            guard let res: LuaClosure = try source.map({UInt8(exactly: $0.unicodeScalars.first?.value ?? 0) ?? 0}).withContiguousStorageIfAvailable({_chunk in
                return LuaClosure(for: try LuaInterpretedFunction(decoding: UnsafeRawBufferPointer(_chunk), named: name?.bytes), with: [LuaUpvalue(with: .table(env))], environment: env)
            }) else {throw Lua.LuaError.runtimeError(message: "could not allocate memory")}
            return res
        } else {
            if mode != .text && mode != .any {
                throw Lua.LuaError.runtimeError(message: "attempt to load a text chunk")
            }
            var called = false
            var source = source
            if source.hasPrefix("#") {
                source = String(source[source.index(after: source.firstIndex(of: "\n") ?? source.index(before: source.endIndex))...])
            }
            return try await load(using: {if !called {called = true; return source.bytes} else {return nil}}, named: name?.bytes ?? "[string '\(source[source.startIndex..<(source.index(source.startIndex, offsetBy: 30, limitedBy: source.endIndex) ?? source.endIndex)])']", mode: mode, environment: env)
        }
    }

    public static func load(from source: [UInt8], named name: [UInt8]?, mode: LoadMode, environment env: LuaTable) async throws -> LuaClosure {
        if source.starts(with: "\u{1b}Lua" as [UInt8]) {
            if mode != .binary && mode != .any {
                throw Lua.LuaError.runtimeError(message: "attempt to load a binary chunk")
            }
            guard let res: LuaClosure = try source.withContiguousStorageIfAvailable({_chunk in
                return LuaClosure(for: try LuaInterpretedFunction(decoding: UnsafeRawBufferPointer(_chunk), named: name), with: [LuaUpvalue(with: .table(env))], environment: env)
            }) else {throw Lua.LuaError.runtimeError(message: "could not allocate memory")}
            return res
        } else {
            if mode != .text && mode != .any {
                throw Lua.LuaError.runtimeError(message: "attempt to load a text chunk")
            }
            var called = false
            var source = source
            if source.starts(with: "#" as [UInt8]) {
                source = [UInt8](source[source.index(after: source.firstIndex(of: "\n") ?? source.index(before: source.endIndex))...])
            }
            return try await load(using: {if !called {called = true; return source} else {return nil}}, named: name ?? "[string '\(source[source.startIndex..<(source.index(source.startIndex, offsetBy: 30, limitedBy: source.endIndex) ?? source.endIndex)])']", mode: mode, environment: env)
        }
    }

    public static func load(using loader: @escaping () async throws -> [UInt8]?, named name: [UInt8]?, mode: LoadMode, environment env: LuaTable) async throws -> LuaClosure {
        if var start = try await loader() {
            while start.count < 4 {
                if let c = try await loader() {
                    start += c
                } else {
                    break
                }
            }
            if start.starts(with: "\u{1b}Lua" as [UInt8]) {
                if mode != .binary && mode != .any {
                    throw Lua.LuaError.runtimeError(message: "attempt to load a binary chunk")
                }
                while true {
                    if let c = try await loader() {
                        start += c
                    } else {
                        break
                    }
                }
                guard let res: LuaClosure = try start.withContiguousStorageIfAvailable({_chunk in
                    return LuaClosure(for: try LuaInterpretedFunction(decoding: UnsafeRawBufferPointer(_chunk), named: name), with: [LuaUpvalue(with: .table(env))], environment: env)
                }) else {throw Lua.LuaError.runtimeError(message: "could not allocate memory")}
                return res
            } else {
                if mode != .text && mode != .any {
                    throw Lua.LuaError.runtimeError(message: "attempt to load a text chunk")
                }
                var first: [UInt8]? = start
                let fn = try await LuaParser.parse(from: LuaLexer(using: {
                    if let v = first {
                        first = nil
                        return v
                    }
                    return try await loader()
                }, named: name ?? "?"))
                return LuaClosure(for: fn, with: [LuaUpvalue(with: .table(env))], environment: env)
            }
        } else {
            return try await load(from: "", named: name, mode: mode, environment: env)
        }
    }

    public static func test() -> LuaInterpretedFunction {
        return LuaCode.test()
    }
}
