import XCTest
@testable import Lua
import LuaLib

final class LuaTests: XCTestCase {
    // XCTest Documenation
    // https://developer.apple.com/documentation/xctest

    // Defining Test Cases and Test Methods
    // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods

    private func doTest(named name: String) async throws {
        let state = await LuaState(withLibraries: true)
        await state.globalTable!.isolated {env in
            env["arg"] = .table(LuaTable())
            env["_soft"] = .boolean(true)
            env["_port"] = .boolean(true)
            env["_no32"] = .boolean(false)
            env["_nomsg"] = .boolean(false)
            env["_noposix"] = .boolean(false)
            env["_nolonglong"] = .boolean(false)
            env["_noformatA"] = .boolean(false)
            env["require"] = .function(.swift(LuaSwiftFunction {state, args in [await env[args[1]]]}))
            env["collectgarbage"] = .function(.swift(.empty))
        }
        print("==> Loading test \(name)")
        let cl = try await LuaLoad.load(from: try String(contentsOf: URL(fileURLWithPath: "LuaTests/" + name), encoding: .isoLatin1), named: "@" + name, mode: .text, environment: .table(state.globalTable!), in: state)
        let fn = LuaFunction.lua(cl)
        try Data(await cl.proto.dump()).write(to: URL(fileURLWithPath: "LuaTests/\(name)c"))
        print("==> Running test \(name)")
        let res2 = try await fn.call(in: state.currentThread, with: [])
        print("==> Test \(name) results:")
        for v in res2 {print(v)}
    }

    func testAttrib() async throws {try await doTest(named: "attrib.lua")}
    func testBig() async throws {try await doTest(named: "big.lua")}
    func testBitwise() async throws {try await doTest(named: "bitwise.lua")}
    func testCalls() async throws {try await doTest(named: "calls.lua")}
    func testChecktable() async throws {try await doTest(named: "checktable.lua")}
    func testClosure() async throws {try await doTest(named: "closure.lua")}
    func testCode() async throws {try await doTest(named: "code.lua")}
    func testConstructs() async throws {try await doTest(named: "constructs.lua")}
    func testCoroutine() async throws {try await doTest(named: "coroutine.lua")}
    func testDb() async throws {try await doTest(named: "db.lua")}
    func testErrors() async throws {try await doTest(named: "errors.lua")}
    func testEvents() async throws {try await doTest(named: "events.lua")}
    func testFiles() async throws {try await doTest(named: "files.lua")}
    func testGc() async throws {try await doTest(named: "gc.lua")}
    func testGoto() async throws {try await doTest(named: "goto.lua")}
    func testLiterals() async throws {try await doTest(named: "literals.lua")}
    func testLocals() async throws {try await doTest(named: "locals.lua")}
    func testMain() async throws {try await doTest(named: "main.lua")}
    func testMath() async throws {try await doTest(named: "math.lua")}
    func testNextvar() async throws {try await doTest(named: "nextvar.lua")}
    func testPm() async throws {try await doTest(named: "pm.lua")}
    func testSort() async throws {try await doTest(named: "sort.lua")}
    func testStrings() async throws {try await doTest(named: "strings.lua")}
    func testVararg() async throws {try await doTest(named: "vararg.lua")}
    func testVerybig() async throws {try await doTest(named: "verybig.lua")}

    func testLuaObject() async throws {
        let state = await LuaState(withLibraries: true)
        let env = await state.globalTable!
        await env.set(index: "obj", value: .object(TestObject()))
        let cl = try await LuaLoad.load(from: """
            obj:testNoArgs()
            obj:testOneArg(2)
            obj:testOneNamedArg(3)
            obj:testOneOptionalArg(nil)
            assert(obj:testNoArgsReturn() == "no args")
            assert(obj:testTwoArgsReturn(string, "find") == string.find)
            assert(obj:testOptionalReturn() == nil)
            local a, b = obj:testTupleReturn()
            assert(a == 51 and b == 19)
            obj:testWithState()
            assert(obj:testWithStateAndTwoArgs(3, 5) == 15)
            assert(obj:testVararg(1, 2, 3) == 3)
            assert(obj:testVarargWithState(1) == 1)
            assert(pcall(obj.testThrows, obj, {}))
            assert(not pcall(obj.testThrows, obj, 9))
            assert(obj["unknown"] == "unknown")
            assert(string.find(tostring(obj), "TestObject"))
            assert(obj.testStatic(1, 2, 3) == 3)
            obj["unknown"] = "LuaObject works OK"
            return true
            """, named: name, mode: .text, environment: .table(env), in: state)
        let fn = LuaFunction.lua(cl)
        print("==> Running test LuaObject")
        let res2 = try await fn.call(in: state.currentThread, with: [])
        print("==> Test LuaObject results:")
        for v in res2 {print(v)}
    }

    func testLuaLibrary() async throws {
        let state = await LuaState(withLibraries: true)
        let env = await state.globalTable!
        await env.load(library: TestLibrary())
        let cl = try await LuaLoad.load(from: """
            assert(test._VERSION == "1.0")
            assert(test.getValue() == "test")
            test.setValue("abcd")
            assert(test.getValue() == "abcd")
            print("LuaLibrary works OK")
            return true
            """, named: name, mode: .text, environment: .table(env), in: state)
        let fn = LuaFunction.lua(cl)
        print("==> Running test LuaLibrary")
        let res2 = try await fn.call(in: state.currentThread, with: [])
        print("==> Test LuaLibrary results:")
        for v in res2 {print(v)}
    }
}

@LuaObject
public final class TestObject {
    public func testNoArgs() {
        
    }
    
    public func testOneArg(_ a: Int) {
        
    }
    
    public func testOneNamedArg(a: Int) {
        
    }
    
    public func testOneOptionalArg(_ opt: Int?) {
        
    }
    
    public func testNoArgsReturn() -> String {
        return "no args"
    }
    
    public func testTwoArgsReturn(_ a: LuaTable, _ b: LuaValue) async -> LuaValue {
        return await a[b]
    }
    
    public func testOptionalReturn() -> String? {
        return nil
    }
    
    public func testTupleReturn() -> (Int, Int) {
        return (51, 19)
    }
    
    public func testWithState(state: Lua) {
        
    }
    
    public func testWithStateAndTwoArgs(_ state: Lua, a: Int, b: Double) -> Double {
        return Double(a) * b
    }
    
    public func testVararg(_ args: LuaArgs) -> Int {
        return args.count
    }
    
    public func testVarargWithState(_ state: Lua, _ args: LuaArgs) -> [LuaValue] {
        return args.args
    }
    
    public func testThrows(state: Lua, a: LuaValue) throws -> LuaTable {
        guard case let .table(t) = a else {
            throw Lua.LuaError.luaError(message: .string(.string("not a table")))
        }
        return t
    }
    
    public func testYields(state: Lua, _ t: LuaThread) async throws -> [LuaValue] {
        return try await t.resume(in: state)
    }

    public static func testStatic(_ args: LuaArgs) -> Int {
        return args.count
    }

    public subscript(index: LuaValue) -> LuaValue {
        get {
            return index
        } set (value) {
            print(value)
        }
    }
}

@LuaLibrary(named: "test")
public actor TestLibrary {
    private var value: String = "test"

    public static let _VERSION = "1.0"

    public func getValue() -> String {
        return value
    }

    public func setValue(_ val: String) {
        value = val
    }
}
