import XCTest
@testable import Lua
import LuaLib

final class LuaTests: XCTestCase {
    // XCTest Documenation
    // https://developer.apple.com/documentation/xctest

    // Defining Test Cases and Test Methods
    // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods

    private func doTest(named name: String) async throws {
        let state = LuaState(withLibraries: true)
        let env = state.globalTable!
        env["arg"] = .table(LuaTable())
        env["_soft"] = .boolean(true)
        env["_port"] = .boolean(true)
        env["_no32"] = .boolean(false)
        env["_nomsg"] = .boolean(false)
        env["_noposix"] = .boolean(false)
        env["_nolonglong"] = .boolean(false)
        env["_noformatA"] = .boolean(false)
        env["require"] = .function(.swift(.empty))
        env["collectgarbage"] = .function(.swift(.empty))
        print("==> Loading test \(name)")
        let cl = try await LuaLoad.load(from: try String(contentsOf: URL(fileURLWithPath: "LuaTests/" + name), encoding: .isoLatin1), named: name, mode: .text, environment: env)
        let fn = LuaFunction.lua(cl)
        try Data(cl.proto.dump()).write(to: URL(fileURLWithPath: "LuaTests/\(name)c"))
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
}
