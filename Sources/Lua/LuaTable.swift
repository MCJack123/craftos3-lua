public class LuaTable: Hashable {
    public static func == (lhs: LuaTable, rhs: LuaTable) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(self).toOpaque())
    }

    private class MaybeWeakValue: Hashable {
        private enum VarType {
            case strong
            case weakValueType // stores nothing
            case weakLuaFunction
            case weakSwiftFunction
            case weakUserdata
            case weakThread
            case weakTable
        }
        private let type: VarType
        private let strongValue: LuaValue?
        private weak var weakLuaFunction: LuaClosure?
        private weak var weakSwiftFunction: LuaSwiftFunction?
        private weak var weakUserdata: LuaUserdata?
        private weak var weakThread: LuaThread?
        private weak var weakTable: LuaTable?

        convenience init(_ val: LuaValue, isWeak: Bool) {
            if isWeak {
                self.init(weakly: val)
            } else {
                self.init(strongly: val)
            }
        }

        init(strongly val: LuaValue) {
            type = .strong
            strongValue = val
        }

        init(weakly val: LuaValue) {
            strongValue = nil
            switch val {
                case .function(let fn):
                    switch fn {
                        case .lua(let cl):
                            type = .weakLuaFunction
                            weakLuaFunction = cl
                        case .swift(let sfn):
                            type = .weakSwiftFunction
                            weakSwiftFunction = sfn
                    }
                case .userdata(let ud):
                    type = .weakUserdata
                    weakUserdata = ud
                case .thread(let th):
                    type = .weakThread
                    weakThread = th
                case .table(let t):
                    type = .weakTable
                    weakTable = t
                default:
                    type = .weakValueType
            }
        }

        var value: LuaValue {
            switch type {
                case .strong: return strongValue!
                case .weakLuaFunction:
                    if let v = weakLuaFunction {return .function(.lua(v))}
                    return .nil
                case .weakSwiftFunction:
                    if let v = weakSwiftFunction {return .function(.swift(v))}
                    return .nil
                case .weakUserdata:
                    if let v = weakUserdata {return .userdata(v)}
                    return .nil
                case .weakThread:
                    if let v = weakThread {return .thread(v)}
                    return .nil
                case .weakTable:
                    if let v = weakTable {return .table(v)}
                    return .nil
                case .weakValueType:
                    return .nil
            }
        }

        static func == (lhs: LuaTable.MaybeWeakValue, rhs: LuaTable.MaybeWeakValue) -> Bool {
            return lhs.value == rhs.value
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(value)
        }
    }

    private var hash = [MaybeWeakValue: MaybeWeakValue]()
    private var array = [MaybeWeakValue]() // TODO: resize array part
    private var weakKeys = false
    private var weakValues = false

    private var _metatable: LuaTable? = nil
    public var metatable: LuaTable? {
        get {
            return _metatable
        } set (value) {
            _metatable = value
            if case let .string(mode) = value?["__mode"] {
                if mode.string.contains("k") && !weakKeys {
                    weakKeys = true
                    array = [] // numbers are never referenced => empty array portion
                    let hash = self.hash
                    self.hash = [MaybeWeakValue: MaybeWeakValue]()
                    for (k, v) in hash {
                        self.hash[MaybeWeakValue(weakly: k.value)] = v
                    }
                }
                if mode.string.contains("v") && !weakValues {
                    weakValues = true
                    for i in 0..<array.count {
                        array[i] = MaybeWeakValue(weakly: array[i].value)
                    }
                    for (k, v) in hash {
                        self.hash[k] = MaybeWeakValue(weakly: v.value)
                    }
                }
            } else if weakKeys || weakValues {
                if weakKeys {
                    let hash = self.hash
                    self.hash = [MaybeWeakValue: MaybeWeakValue]()
                    for (k, v) in hash {
                        self.hash[MaybeWeakValue(strongly: k.value)] = v
                    }
                }
                if weakValues {
                    for i in 0..<array.count {
                        array[i] = MaybeWeakValue(strongly: array[i].value)
                    }
                    for (k, v) in hash {
                        self.hash[k] = MaybeWeakValue(strongly: v.value)
                    }
                }
                weakKeys = false
                weakValues = false
            }
        }
    }
    public var state: LuaState? = nil
    public var count: Int {
        var j = array.count
        if j > 0 && array.last?.value == .nil {
            var i = 0
            while j - i > 1 {
                let m = (i + j) / 2
                if array[m - 1].value == .nil {
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
        self.hash = [MaybeWeakValue: MaybeWeakValue](minimumCapacity: hash)
        self.array = [MaybeWeakValue](repeating: MaybeWeakValue(strongly: .nil), count: array)
        self.state = state
    }

    public init(hash: Int, array: Int, state: Lua) {
        self.hash = [MaybeWeakValue: MaybeWeakValue](minimumCapacity: hash)
        self.array = [MaybeWeakValue](repeating: MaybeWeakValue(strongly: .nil), count: array)
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
            .map {MaybeWeakValue(strongly: $1.1)}
        let hash = dict.filter {
            if case let .number(n) = $0.key, let i = Int(exactly: n), i > 0 && i <= self.array.count {return false}
            else {return true}
        }
        for (k, v) in hash {
            self.hash[MaybeWeakValue(strongly: k)] = MaybeWeakValue(strongly: v)
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
                    if array[i-1].value != .nil {
                        return .number(Double(i))
                    }
                }
            }
            if hash.isEmpty {
                return .nil
            } else {
                return hash[hash.startIndex].key.value
            }
        } else if case var .number(n) = key, Int(exactly: n) != nil && n > 0 && Int(n) <= array.count {
            while true {
                if Int(n) + 1 == array.count {
                    if hash.isEmpty {
                        return .nil
                    } else {
                        return hash[hash.startIndex].key.value
                    }
                } else if array[Int(n) + 1].value != .nil {
                    return .number(n + 1)
                }
                n += 1
            }
        } else if let idx = hash.index(forKey: MaybeWeakValue(strongly: key)) {
            let next = hash.index(after: idx)
            if next == hash.endIndex {return .nil}
            return hash[next].key.value
        } else {
            return .nil // TODO: handle keys not in the table
        }
    }

    public subscript(index: LuaValue) -> LuaValue {
        get {
            if case let .number(n) = index, Int(exactly: n) != nil && n > 0 && Int(n) <= array.count {
                return array[Int(n)-1].value
            }
            return hash[MaybeWeakValue(strongly: index)]?.value ?? .nil
        } set (value) {
            if case let .number(n) = index, Int(exactly: n) != nil && n > 0 && Int(n) <= array.count {
                if !weakKeys {
                    array[Int(n)-1] = MaybeWeakValue(value, isWeak: weakValues)
                }
            } else if value != .nil {
                hash[MaybeWeakValue(index, isWeak: weakKeys)] = MaybeWeakValue(value, isWeak: weakValues)
            } else {
                hash[MaybeWeakValue(strongly: index)] = nil
            }
        }
    }

    public subscript(index: String) -> LuaValue {
        get {
            return hash[MaybeWeakValue(strongly: .string(.string(index)))]?.value ?? .nil
        } set (value) {
            if weakKeys {return}
            if value != .nil {
                hash[MaybeWeakValue(strongly: .string(.string(index)))] = MaybeWeakValue(value, isWeak: weakValues)
            } else {
                hash[MaybeWeakValue(strongly: .string(.string(index)))] = nil
            }
        }
    }

    public subscript(index: Int) -> LuaValue {
        get {
            if index > 0 && index <= array.count {
                return array[index-1].value
            }
            return hash[MaybeWeakValue(strongly: .number(Double(index)))]?.value ?? .nil
        } set (value) {
            if weakKeys {return}
            if index > 0 && index <= array.count {
                array[index-1] = MaybeWeakValue(value, isWeak: weakValues)
            } else if value != .nil {
                hash[MaybeWeakValue(strongly: .number(Double(index)))] = MaybeWeakValue(value, isWeak: weakValues)
            } else {
                hash[MaybeWeakValue(strongly: .number(Double(index)))] = nil
            }
        }
    }
}
