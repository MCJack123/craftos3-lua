import Foundation

public class LuaTable: Hashable {
    public static func == (lhs: LuaTable, rhs: LuaTable) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hash)
        hasher.combine(array)
        hasher.combine(metatable)
    }

    private var hash = [LuaValue: LuaValue]()
    private var array = [LuaValue]() // TODO: resize array part

    public var metatable: LuaTable? = nil
    public var count: Int {
        var j = array.count
        if j > 0 && array.last == .nil {
            var i = 0
            while j - i > 1 {
                let m = (i + j) / 2
                if array[m - 1] == .nil {
                    j = m
                } else {
                    i = m
                }
            }
            return i
        } else if hash.count == 0 {
            return j
        } else {
            var i = j
            j += 1
            while self[j] != .nil {
                i = j
                let jj = j.multipliedReportingOverflow(by: 2)
                j = jj.partialValue
                if jj.overflow {
                    i = 1
                    while self[i] != .nil {i+=1}
                    return i - 1
                }
            }
            while j - i > 1 {
                let m = (i + j / 2)
                if self[m] == .nil {
                    j = m
                } else {
                    i = m
                }
            }
            return i
        }
    }

    public init() {}

    public init(hash: Int, array: Int) {
        self.hash = [LuaValue: LuaValue](minimumCapacity: hash)
        self.array = [LuaValue](repeating: .nil, count: array)
    }

    public func load(library: LuaLibrary, name: String? = nil) {
        let nam = name ?? library.name
        hash[.string(.string(nam))] = .table(library.table)
    }

    public func next(key: LuaValue) -> LuaValue {
        if key == .nil {
            if array.isEmpty {
                if hash.isEmpty {
                    return .nil
                } else {
                    return hash[hash.startIndex].key
                }
            } else {
                return .number(1)
            }
        } else if case let .number(n) = key, Foundation.floor(n) == n && n > 0 && Int(n) <= array.count {
            if Int(n) == array.count {
                if hash.isEmpty {
                    return .nil
                } else {
                    return hash[hash.startIndex].key
                }
            } else {
                return .number(n + 1)
            }
        } else if let idx = hash.index(forKey: key) {
            return hash[hash.index(after: idx)].key
        } else {
            return .nil // TODO: handle keys not in the table
        }
    }

    public subscript(index: LuaValue) -> LuaValue {
        get {
            if case let .number(n) = index, Foundation.floor(n) == n && n > 0 && Int(n) <= array.count {
                return array[Int(n)-1]
            }
            return hash[index] ?? .nil
        } set (value) {
            if case let .number(n) = index, Foundation.floor(n) == n && n > 0 && Int(n) <= array.count {
                array[Int(n)-1] = value
            } else if value != .nil {
                hash[index] = value
            } else {
                hash[index] = nil
            }
        }
    }

    public subscript(index: String) -> LuaValue {
        get {
            return hash[.string(.string(index))] ?? .nil
        } set (value) {
            if value != .nil {
                hash[.string(.string(index))] = value
            } else {
                hash[.string(.string(index))] = nil
            }
        }
    }

    public subscript(index: Int) -> LuaValue {
        get {
            if index > 0 && index <= array.count {
                return array[index-1]
            }
            return hash[.number(Double(index))] ?? .nil
        } set (value) {
            if index > 0 && index <= array.count {
                array[index-1] = value
            } else if value != .nil {
                hash[.number(Double(index))] = value
            } else {
                hash[.number(Double(index))] = nil
            }
        }
    }
}