import Lua

public protocol LuaLibrary {
    var name: String {get}
    var table: LuaTable {get}
}

public extension LuaLibrary {
    var table: LuaTable {
        let tab = LuaTable()
        var names = [String]()
        for child in Mirror(reflecting: self).children {
            if let fn = child.value as? LuaSwiftFunction, let label = child.label {
                names.append(label)
                tab[label] = .function(.swift(fn))
            } else if let val = child.value as? LuaValue, let label = child.label {
                names.append(label)
                tab[label] = val
            }
        }
        //print("Library \(name): \(names.joined(separator: " "))")
        return tab
    }
}

@attached(extension, conformances: LuaLibrary, names: named(table), named(name))
public macro LuaLibrary(named: String) = #externalMacro(module: "LuaMacros", type: "LuaLibraryMacro")

public extension LuaState {
    convenience init(withLibraries: Bool) {
        self.init()
        let _G = BaseLibrary().table
        _G["_G"] = .table(_G)
        _G["_VERSION"] = .string(.string("Lua 5.2"))
        _G.load(library: Bit32Library())
        _G.load(library: CoroutineLibrary())
        _G.load(library: DebugLibrary())
        _G.load(library: IOLibrary())
        _G.load(library: MathLibrary())
        _G.load(library: OSLibrary())
        _G.load(library: StringLibrary())
        _G.load(library: TableLibrary())
        self.stringMetatable = LuaTable(from: [
            .string(.string("__index")): _G["string"]
        ])
        self.globalTable = _G
    }
}

public extension LuaTable {
    func load(library: LuaLibrary, named name: String? = nil) {
        let nam = name ?? library.name
        self[nam] = .table(library.table)
    }
}