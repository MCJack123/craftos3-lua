public class LuaTable: Hashable {
    public static func == (lhs: LuaTable, rhs: LuaTable) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(self).toOpaque())
    }

    private var hash = [LuaValue: LuaValue]()
    private var array = [LuaValue]() // TODO: resize array part

    public var metatable: LuaTable? = nil
    public var state: LuaState? = nil
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
                let m = (i + j) / 2
                if self[m] == .nil {
                    j = m
                } else {
                    i = m
                }
            }
            return i
        }
    }

    public init(state: LuaState? = nil) {
        self.state = state
    }

    public init(state: Lua) {
        self.state = state.thread.luaState
    }

    public init(hash: Int, array: Int, state: LuaState? = nil) {
        self.hash = [LuaValue: LuaValue](minimumCapacity: hash)
        self.array = [LuaValue](repeating: .nil, count: array)
        self.state = state
    }

    public init(hash: Int, array: Int, state: Lua) {
        self.hash = [LuaValue: LuaValue](minimumCapacity: hash)
        self.array = [LuaValue](repeating: .nil, count: array)
        self.state = state.thread.luaState
    }

    public init(from dict: [LuaValue: LuaValue]) {
        self.array = dict
            .compactMap {
                if case let .number(n) = $0.key, let i = Int(exactly: n), i > 0 {return (i, $0.value)}
                else {return nil}
            }.sorted {$0.0 < $1.0}
            .enumerated()
            .prefix(while: {$0 + 1 == $1.0})
            .map {$1.1}
        self.hash = dict.filter {
            if case let .number(n) = $0.key, let i = Int(exactly: n), i > 0 && i <= self.array.count {return false}
            else {return true}
        }
    }

    private init(_ table: LuaTable) {
        self.array = table.array
        self.hash = table.hash
        self.metatable = table.metatable
        self.state = table.state
    }

    deinit {
        if let state = state, let mt = metatable, case .function = mt["__gc"] {
            state.tablesToBeFinalized.append(LuaTable(self))
        }
    }

    public func next(key: LuaValue) -> LuaValue {
        if key == .nil {
            if !array.isEmpty {
                for i in 1...array.count {
                    if array[i-1] != .nil {
                        return .number(Double(i))
                    }
                }
            }
            if hash.isEmpty {
                return .nil
            } else {
                return hash[hash.startIndex].key
            }
        } else if case var .number(n) = key, Int(exactly: n) != nil && n > 0 && Int(n) <= array.count {
            while true {
                if Int(n) + 1 == array.count {
                    if hash.isEmpty {
                        return .nil
                    } else {
                        return hash[hash.startIndex].key
                    }
                } else if array[Int(n) + 1] != .nil {
                    return .number(n + 1)
                }
                n += 1
            }
        } else if let idx = hash.index(forKey: key) {
            let next = hash.index(after: idx)
            if next == hash.endIndex {return .nil}
            return hash[next].key
        } else {
            return .nil // TODO: handle keys not in the table
        }
    }

    public subscript(index: LuaValue) -> LuaValue {
        get {
            if case let .number(n) = index, Int(exactly: n) != nil && n > 0 && Int(n) <= array.count {
                return array[Int(n)-1]
            }
            return hash[index] ?? .nil
        } set (value) {
            if case let .number(n) = index, Int(exactly: n) != nil && n > 0 && Int(n) <= array.count {
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