import Lua

public protocol LuaLibrary: Sendable {
    var name: String {get}
    func table() async -> LuaTable
}

public extension LuaLibrary {
    func table() async -> LuaTable {
        let tab = LuaTable()
        var names = [String]()
        for child in Mirror(reflecting: self).children {
            if let fn = child.value as? LuaSwiftFunction, let label = child.label {
                names.append(label)
                await tab.set(index: label, value: .function(.swift(fn)))
            } else if let val = child.value as? LuaValue, let label = child.label {
                names.append(label)
                await tab.set(index: label, value: val)
            }
        }
        //print("Library \(name): \(names.joined(separator: " "))")
        return tab
    }
}

@attached(extension, conformances: LuaLibrary, names: named(table), named(name))
public macro LuaLibrary(named: String) = #externalMacro(module: "LuaMacros", type: "LuaLibraryMacro")

public extension LuaState {
    init(withLibraries: Bool) async {
        await self.init()
        let _G = await BaseLibrary().table()
        await _G.set(index: "_G", value: .table(_G))
        await _G.set(index: "_VERSION", value: .string(.string("Lua 5.2")))
        let package = PackageLibrary()
        await _G.set(index: "require", value: .function(.swift(package._require)))
        await _G.load(library: Bit32Library(), into: package)
        await _G.load(library: CoroutineLibrary(), into: package)
        await _G.load(library: DebugLibrary(), into: package)
        await _G.load(library: IOLibrary(), into: package)
        await _G.load(library: MathLibrary(), into: package)
        await _G.load(library: OSLibrary(), into: package)
        await _G.load(library: package, into: package)
        await _G.load(library: StringLibrary(), into: package)
        await _G.load(library: TableLibrary(), into: package)
        self.stringMetatable = await LuaTable(from: [
            .string(.string("__index")): _G["string"]
        ])
        self.globalTable = _G
    }
}

public extension LuaTable {
    func load(library: LuaLibrary, named name: String? = nil, into package: PackageLibrary? = nil) async {
        let nam = name ?? library.name
        let t = LuaValue.table(await library.table())
        self[nam] = t
        if let package = package {
            await package.add(t, named: nam)
        }
    }
}