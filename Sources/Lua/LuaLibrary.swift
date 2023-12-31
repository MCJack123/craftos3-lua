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
            }
        }
        print("Library \(name): \(names.joined(separator: " "))")
        return tab
    }
}