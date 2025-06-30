import Lua
import Foundation

@LuaLibrary(named: "package")
public final class PackageLibrary {
    #if os(Windows)
    public static let config = "\\\n;\n?\n!\n-"
    #else
    public static let config = "/\n;\n?\n!\n-"
    #endif

    #if os(Windows)
    public static let swiftpath = "!\\?.dll;!\\loadall.dll;.\\?.dll"
    #elseif os(macOS)
    public static let swiftpath = "/usr/local/lib/lua/craftos3-lua/?.dylib;/usr/local/lib/lua/craftos3-lua/?.bundle;/usr/local/lib/lua/craftos3-lua/?.so;/usr/local/lib/lua/craftos3-lua/loadall.dylib;/usr/local/lib/lua/craftos3-lua/loadall.bundle;/usr/local/lib/lua/craftos3-lua/loadall.so;./?.dylib;./?.bundle;./?.so"
    #else
    public static let swiftpath = "/usr/local/lib/lua/craftos3-lua/?.so;/usr/local/lib/lua/craftos3-lua/loadall.so;./?.so"
    #endif

    #if os(Windows)
    public static let path = "!\\lua\\?.lua;!\\lua\\?\\init.lua;!\\?.lua;!\\?\\init.lua;.\\?.lua;.\\?\\init.lua"
    #else
    public static let path = "/usr/local/share/lua/craftos3-lua/?.lua;/usr/local/share/lua/craftos3-lua/lua/?/init.lua;/usr/local/lib/lua/craftos3-lua/?.lua;/usr/local/lib/lua/craftos3-lua/?/init.lua;./?.lua;./?/init.lua"
    #endif

    private let loaded = LuaTable()
    private let preload = LuaTable()
    private let sentinel = LuaTable()

    public func loadlib(_ libname: String, _ funcname: String) -> LuaFunction? {
        return nil
    }

    public func searchpath(_ name: String, _ path: String, _ sep: String?, _ rep: Int?) -> [LuaValue] {
        #if os(Windows)
        let pname = name.replacing(".", with: "\\")
        #else
        let pname = name.replacing(".", with: "/")
        #endif
        var err = ""
        for p in path.split(separator: ";") {
            let f = String(p.replacing("?", with: pname))
            if FileManager.default.fileExists(atPath: f) {
                return [.value(f)]
            } else {
                if !err.isEmpty {err += "\n\t"}
                err += "no file '\(f)'"
            }
        }
        return [.nil, .value(err)]
    }

    internal func require(_ state: Lua, _ name: String) async throws -> LuaValue {
        if let val = await loaded[name].optional {
            if case let .table(tbl) = val, tbl == sentinel {
                throw await Lua.error(in: state, message: "loop detected while loading module '\(name)'")
            }
            return val
        }
        let searchers = try await state.global(named: "package").index(.value("searchers"), in: state)
        var i = 1
        var err = "module '\(name)' not found:"
        while true {
            guard let searcher = try await searchers.index(.value(i), in: state).optional else {break}
            let res = try await searcher.call(with: [.value(name)], in: state)
            if let loader = res.first?.optional {
                await loaded.set(index: name, value: .table(sentinel))
                let val = try await loader.call(with: [.value(name), res.count > 1 ? res[1] : .nil], in: state)
                if let mod = val.first?.optional {
                    await loaded.set(index: name, value: mod)
                } else if case let .table(tbl) = await loaded[name], tbl == sentinel {
                    await loaded.set(index: name, value: .boolean(true))
                }
                return await loaded[name]
            } else if res.count > 1 {
                err += "\n\t" + (await res[1].toString)
            }
            i += 1
        }
        throw await state.error(err)
    }

    internal var _require: LuaSwiftFunction {
        return LuaSwiftFunction {state, args in
            return [try await self.require(state, try await args.checkString(at: 1))]
        }
    }

    internal func add(_ library: LuaValue, named name: String) async {
        await loaded.set(index: name, value: library)
    }

    private static func luaLoader(_ state: Lua, _ name: String, _ path: String) async throws -> LuaValue {
        let fn = LuaFunction.lua(try await LuaLoad.load(from: try String(contentsOf: URL(fileURLWithPath: path), encoding: .isoLatin1), named: "@" + path, mode: .any, environment: .table(state.luaState.globalTable!), in: state))
        let res = try await fn.call(in: state.thread, with: [.value(name), .value(path)])
        return res.first ?? .nil
    }

    private static func swiftLoader(_ state: Lua, _ name: String, _ path: String) async throws -> LuaValue {
        throw Lua.LuaError.internalError
    }

    private func setup(table package: LuaTable) async {
        await package.set(index: "loaded", value: .table(loaded))
        await package.set(index: "preload", value: .table(preload))
        await package.set(index: "searchers", value: .table(LuaTable(from: [
            .value(LuaSwiftFunction {state, args in
                if let val = await self.preload[args[1]].optional {
                    return [.value(LuaSwiftFunction {_, a in [a[1]]}), val]
                } else {
                    return [.nil, .value("no field package.preload['\(await args[1].toString)']")]
                }
            }),
            .value(LuaSwiftFunction {state, args in
                let res = self.searchpath(try await args.checkString(at: 1), await package["path"].toString, nil, nil)
                if res[0] != .nil {
                    return [.value(LuaSwiftFunction {_state, _args in 
                        return [try await PackageLibrary.luaLoader(_state, try await _args.checkString(at: 1), try await _args.checkString(at: 2))]
                    }), res[0]]
                } else {
                    return res
                }
            }),
            .value(LuaSwiftFunction {state, args in
                let res = self.searchpath(try await args.checkString(at: 1), await package["swiftpath"].toString, nil, nil)
                if res[0] != .nil {
                    return [.value(LuaSwiftFunction {_state, _args in 
                        return [try await PackageLibrary.swiftLoader(_state, try await _args.checkString(at: 1), try await _args.checkString(at: 2))]
                    }), res[0]]
                } else {
                    return res
                }
            }),
            .value(LuaSwiftFunction {state, args in
                let res = self.searchpath(String(try await args.checkString(at: 1).prefix {$0 != "."}), await package["swiftpath"].toString, nil, nil)
                if res[0] != .nil {
                    return [.value(LuaSwiftFunction {_state, _args in 
                        return [try await PackageLibrary.swiftLoader(_state, try await _args.checkString(at: 1), try await _args.checkString(at: 2))]
                    }), res[0]]
                } else {
                    return res
                }
            }),
        ])))
    }
}
