public actor LuaState {
    public var nilMetatable: LuaTable? = nil
    public var booleanMetatable: LuaTable? = nil
    public var numberMetatable: LuaTable? = nil
    public var stringMetatable: LuaTable? = nil
    public var functionMetatable: LuaTable? = nil
    public var threadMetatable: LuaTable? = nil
    public var currentThread: LuaThread!
    public var tablesToBeFinalized = [LuaTable]()
    public var globalTable: LuaTable!
    public var registry: LuaTable!

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
            case .userdata(let t): await t.set(metatable: table)
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
}