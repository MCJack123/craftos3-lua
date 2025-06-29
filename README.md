# craftos3-lua
A Lua VM/runtime written in pure Swift 6 (with some libc imports). Work-in-progress, but basic features are functional.

## Rationale
I've been using PUC Lua for many years in [CraftOS-PC 2](https://github.com/MCJack123/craftos2), and the most frustrating thing I had to deal with was random crashes due to memory issues. The second most frustrating thing was trying to implement new features in the garbage collector without causing said memory issues.

To reduce the amount of time I spend debugging race conditions and memory bugs, I wanted to rewrite the entire codebase in a safe language, starting from the ground up. I'm not a big fan of Rust (it's too complicated for me and is somewhat limiting in what kinds of design patterns I can use), so I decided to use a language more familiar to me, Swift.

While Swift was originally created for Apple platforms, over the years it has expanded its availablility across all desktop platforms, as well as Android (soon). In the past I was hesitant to use it due to its limited cross-platform support, but nowadays I believe that Swift is mature enough on other platforms (especially Windows) that it's fine to start writing in.

## Usage
Add the library to your `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/MCJack123/craftos3-lua.git", .branch("master"))
],
targets: [
    .target(
        name: "MyPackage",
        dependencies: [
            .product(name: "Lua", package: "craftos3-lua"),
            .product(name: "LuaLib", package: "craftos3-lua") // optional, for standard libraries
        ])
]
```

A new state can be created using the `LuaState` constructors:
```swift
import Lua
import LuaLib // imports standard Lua library; optional

let state = await LuaState()
let stateWithLibraries = await LuaState(withLibraries: true) // sets up _G environment with all libraries; requires LuaLib
```

Example of compiling and calling Lua code:
```swift
let env = await state.globalTable!
let cl = try await LuaLoad.load(from: """
    local arg1 = ...
    print("Hello World!", arg1)
    return 10
    """, named: name, mode: .text, environment: .table(env), in: state)
let fn = LuaFunction.lua(cl)
let res = try await fn.call(in: state.currentThread, with: [.value("Argument")])
for v in res {
    print(v)
}
```

For custom global libraries written in Swift, you can use the `@LuaLibrary` macro to make a library class with automatic type checking:
```swift
@LuaLibrary(named: "mylib")
public actor MyLibrary {
    private var value: String = "hello"

    public static let _VERSION = "1.0"

    public func getValue() -> String {
        return value
    }

    public func setValue(_ val: String) {
        value = val
    }
}

await env.load(library: MyLibrary())
let fn = LuaFunction.lua(try await LuaLoad.load(from: """
    print(mylib._VERSION)
    print(mylib.getValue())
    mylib.setValue("abcd")
    print(mylib.getValue())
    """, named: name, mode: .text, environment: .table(env), in: state))
try await fn.call(in: state.currentThread, with: [])
```

## License
This code is licensed under the MIT license, just like PUC Lua. See `LICENSE` for more details.
