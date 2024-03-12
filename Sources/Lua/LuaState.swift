public class LuaState {
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

    public init() {
        registry = LuaTable(state: self)
        currentThread = LuaThread(in: self)
        globalTable = LuaTable(state: self)
    }
}