public class LuaTable: Hashable {
    public static func == (lhs: LuaTable, rhs: LuaTable) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(members)
        hasher.combine(metatable)
    }

    public var metatable: LuaTable? = nil
    public var members = [LuaValue: LuaValue]()
    public var count: Int {
        // TODO: fix count
        return members.count
    }

    public init() {}

    public func load(library: LuaLibrary, name: String? = nil) {
        let nam = name ?? library.name
        members[.string(.string(nam))] = .table(library.table)
    }

    public subscript(index: LuaValue) -> LuaValue {
        get {
            return members[index] ?? .nil
        } set (value) {
            if value != .nil {
                members[index] = value
            } else {
                members[index] = nil
            }
        }
    }

    public subscript(index: String) -> LuaValue {
        get {
            return members[.string(.string(index))] ?? .nil
        } set (value) {
            if value != .nil {
                members[.string(.string(index))] = value
            } else {
                members[.string(.string(index))] = nil
            }
        }
    }

    public subscript(index: Int) -> LuaValue {
        get {
            return members[.number(Double(index))] ?? .nil
        } set (value) {
            if value != .nil {
                members[.number(Double(index))] = value
            } else {
                members[.number(Double(index))] = nil
            }
        }
    }
}