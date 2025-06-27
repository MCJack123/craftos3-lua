import Lua
import LuaLib
import Foundation

@main
class lua {
    static func main() async {
        let state = await LuaState(withLibraries: true)
        print("craftos3-lua 5.2\tCopyright (c) 2023-2025 JackMacWindows")
        while true {
            print("> ", separator: "", terminator: "")
            if var line = readLine() {
                if line.starts(with: "=") {line = "return " + line[line.index(after: line.startIndex)...]}
                do {
                    let cl = try await LuaLoad.load(from: line, named: "=stdin", mode: .text, environment: .table(state.globalTable))
                    let res = try await LuaFunction.lua(cl).call(in: state.currentThread, with: [])
                    print(res)
                } catch let error as Lua.LuaError {
                    switch error {
                        case .luaError(let message): print(await message.toString)
                        case .runtimeError(let message): print(message)
                        case .vmError: print("vm error")
                        case .internalError: print("internal error")
                    }
                } catch let error {
                    print(error.localizedDescription)
                }
            } else {
                return
            }
        }
    }
}