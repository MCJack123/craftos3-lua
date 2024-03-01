import Lua

public protocol LuaLibrary {
    var name: String {get}
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

public extension LuaState {
    convenience init(withLibraries: Bool) {
        self.init()
        let _G = BaseLibrary().table
        _G["_G"] = .table(_G)
        _G["_VERSION"] = .string(.string("Lua 5.2"))
        _G["bit32"] = .table(Bit32Library().table)
        _G["coroutine"] = .table(CoroutineLibrary().table)
        _G["math"] = .table(MathLibrary().table)
        _G["os"] = .table(OSLibrary().table)
        _G["string"] = .table(StringLibrary().table)
        _G["table"] = .table(TableLibrary().table)
        self.globalTable = _G
    }
}

public extension LuaTable {
    func load(library: LuaLibrary, name: String? = nil) {
        let nam = name ?? library.name
        self[nam] = .table(library.table)
    }
}