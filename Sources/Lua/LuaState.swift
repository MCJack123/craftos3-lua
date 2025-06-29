internal protocol AsyncEquatable: Sendable {
    func equals(otherAsync: Self) async -> Bool
}

internal protocol AsyncHashable: AsyncEquatable {
    func hash(intoAsync: inout Hasher) async
}

fileprivate struct AsyncSet<Element: AsyncHashable> {
    private var map = [Int: [Element]]()

    public func contains(_ element: Element) async -> Bool {
        var hasher = Hasher()
        await element.hash(intoAsync: &hasher)
        let hash = hasher.finalize()
        if let list = map[hash] {
            return await withTaskGroup { (group: inout TaskGroup<Bool>) in
                for el in list {
                    group.addTask {
                        if await el.equals(otherAsync: element) {
                            return true
                        }
                        return false
                    }
                }
                return await group.contains(true)
            }
        }
        return false
    }

    public mutating func insert(_ element: Element) async -> (inserted: Bool, memberAfterInsert: Element) {
        var hasher = Hasher()
        await element.hash(intoAsync: &hasher)
        let hash = hasher.finalize()
        if let list = map[hash] {
            // for el in list {
            //     if await el.equals(otherAsync: element) {
            //         return (inserted: false, memberAfterInsert: el)
            //     }
            // }
            if let idx = await withTaskGroup(body: { (group: inout TaskGroup<[Element].Index?>) in
                for (index, el) in list.enumerated() {
                    group.addTask {
                        if await el.equals(otherAsync: element) {
                            return index
                        }
                        return nil
                    }
                }
                if let idx = await group.first(where: {$0 != nil}) {return idx}
                return nil
            }) {
                return (inserted: false, memberAfterInsert: list[idx])
            }
            map[hash]!.append(element)
        } else {
            map[hash] = [element]
        }
        return (inserted: true, memberAfterInsert: element)
    }
}

fileprivate extension AsyncSet where Element == LuaClosure {
    func find(function proto: LuaInterpretedFunction, upvalues: [LuaUpvalue]) async -> LuaClosure? {
        var hasher = Hasher()
        hasher.combine(proto)
        for upval in upvalues {
            hasher.combine(Unmanaged.passUnretained(upval).toOpaque())
        }
        let hash = hasher.finalize()
        if let list = map[hash] {
            if let idx = await withTaskGroup(body: { (group: inout TaskGroup<[Element].Index?>) in
                for (index, el) in list.enumerated() {
                    group.addTask {
                        if await el.equals(proto, upvalues) {
                            return index
                        }
                        return nil
                    }
                }
                if let idx = await group.first(where: {$0 != nil}) {return idx}
                return nil
            }) {
                return list[idx]
            }
        }
        return nil
    }
}

public actor LuaState {
    public var nilMetatable: LuaTable? = nil
    public var booleanMetatable: LuaTable? = nil
    public var numberMetatable: LuaTable? = nil
    public var stringMetatable: LuaTable? = nil
    public var functionMetatable: LuaTable? = nil
    public var threadMetatable: LuaTable? = nil
    public var lightuserdataMetatable: LuaTable? = nil
    public var currentThread: LuaThread!
    public var tablesToBeFinalized = [LuaTable]()
    public var globalTable: LuaTable!
    public var registry: LuaTable!
    private var closures = AsyncSet<LuaClosure>()

    public init() async {
        registry = LuaTable(state: self)
        currentThread = LuaThread(in: self)
        globalTable = LuaTable(state: self)
    }

    internal func swap(thread: LuaThread?, isResuming: Bool) async -> LuaThread? {
        let old = currentThread
        if isResuming {await old?.set(state: .normal)}
        else {await thread?.set(state: .running)}
        currentThread = thread
        return old
    }

    internal func assertThread() throws -> LuaThread {
        if currentThread == nil {
            throw LuaThread.CoroutineError.noCoroutine
        }
        unowned let coro = currentThread!
        return coro
    }

    internal func finalizeTables(in thread: LuaThread) async throws {
        if !tablesToBeFinalized.isEmpty {
            for t in tablesToBeFinalized {
                if let mt = await t.metatable, case let .function(gc) = await mt["__gc"] {
                    _ = try await gc.call(in: thread, with: [.table(t)])
                }
            }
            tablesToBeFinalized = []
        }
    }

    internal func add(tableToFinalize table: LuaTable) {
        tablesToBeFinalized.append(table)
    }

    public func setmetatable(value: LuaValue, table: LuaTable?) async {
        switch value {
            case .table(let t): await t.set(metatable: table)
            case .fulluserdata(let t): await t.set(metatable: table)
            case .lightuserdata: lightuserdataMetatable = table
            case .nil: nilMetatable = table
            case .boolean: booleanMetatable = table
            case .number: numberMetatable = table
            case .string: stringMetatable = table
            case .function: functionMetatable = table
            case .thread: threadMetatable = table
        }
    }

    public func global(named name: String) async -> LuaValue {
        return await globalTable[name]
    }

    public func global(named name: String, value: LuaValue) async {
        await globalTable.set(index: name, value: value)
    }

    public func closure(for fn: LuaInterpretedFunction, with upval: [LuaUpvalue]) async -> LuaClosure {
        if let cl = await closures.find(function: fn, upvalues: upval) {
            return cl
        }
        let cl = LuaClosure.create(for: fn, with: upval)
        var closures = self.closures
        _ = await closures.insert(cl)
        self.closures = closures
        return cl
    }
}