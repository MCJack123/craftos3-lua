import Lua
import LibC

typealias FileDescriptor = UnsafeMutablePointer<FILE>

@LuaObject
internal actor FileObject {
    fileprivate let handle: FileDescriptor?

    fileprivate func read(mode: LuaValue, state: Lua) async throws -> LuaValue {
        guard let handle = handle else {
            throw await Lua.error(in: state, message: "attempt to use a closed file")
        }
        if feof(handle) != 0 {
            return .nil
        }
        if case let .string(mode) = mode {
            var mode = mode.string
            if mode.starts(with: "*") {mode = String(mode[mode.index(after: mode.startIndex)...])}
            switch mode {
                case "a":
                    var retval = [UInt8]()
                    while feof(handle) == 0 {
                        retval.append(contentsOf: [UInt8](unsafeUninitializedCapacity: 4096) {mem, size in
                            size = fread(UnsafeMutableRawPointer(mem.baseAddress), 4096, 1, handle)
                        })
                    }
                    return .string(.string(String(bytes: retval, encoding: .isoLatin1)!))
                case "l", "L":
                    var ptr = UnsafeMutablePointer<CChar>(bitPattern: 0)
                    var size: size_t = 0
                    getline(&ptr, &size, handle)
                    defer {free(ptr)}
                    var str = String(bytes: [UInt8](unsafeUninitializedCapacity: size) {mem, _size in
                        _size = size
                        ptr?.withMemoryRebound(to: UInt8.self, capacity: size) {_ptr in
                            mem.baseAddress?.initialize(from: _ptr, count: size)
                        }
                    }, encoding: .isoLatin1)!
                    if mode == "l" {
                        str.removeLast()
                    }
                    return .string(.string(str))
                case "n":
                    var c: CInt = 0
                    repeat {
                        c = getc(handle)
                    } while (c < 0x30 || c > 0x39) && feof(handle) == 0
                    if feof(handle) != 0 {
                        return .nil
                    }
                    var str = ""
                    repeat {
                        str.append(Character(Unicode.Scalar(UInt32(c))!))
                        c = getc(handle)
                    } while (c >= 0x30 && c <= 0x39) || feof(handle) != 0
                    ungetc(c, handle)
                    return .number(Double(str)!)
                default: throw Lua.LuaError.runtimeError(message: "bad argument (invalid mode)")
            }
        } else if case let .number(n) = mode {
            return .string(.string(String(bytes: [UInt8](unsafeUninitializedCapacity: Int(n)) {mem, size in
                size = fread(UnsafeMutableRawPointer(mem.baseAddress), Int(n), 1, handle)
            }, encoding: .isoLatin1)!))
        } else {
            return .nil
        }
    }

    public func close(_ state: Lua) async throws {
        guard let handle = handle else {
            throw await Lua.error(in: state, message: "attempt to use a closed file")
        }
        fclose(handle)
    }

    public func flush(_ state: Lua) async throws {
        guard let handle = handle else {
            throw await Lua.error(in: state, message: "attempt to use a closed file")
        }
        fflush(handle)
    }

    public func lines(_ state: Lua, _ args: LuaArgs) async -> LuaValue {
        return .function(.swift(LuaSwiftFunction {_state, _args in
            if args.count == 0 {
                return [try await self.read(mode: .string(.string("l")), state: _state)]
            }
            var retval = [LuaValue]()
            for i in 1...args.count {
                retval.append(try await self.read(mode: args[i], state: _state))
            }
            return retval
        }))
    }

    public func read(_ state: Lua, _ args: LuaArgs) async throws -> [LuaValue] {
        if args.count == 0 {
            return [try await self.read(mode: .string(.string("l")), state: state)]
        }
        var retval = [LuaValue]()
        for i in 1...args.count {
            retval.append(try await self.read(mode: args[i], state: state))
        }
        return retval
    }

    public func setvbuf(_ state: Lua, mode: String, size: Int?) async throws {
        guard let handle = handle else {
            throw await Lua.error(in: state, message: "attempt to use a closed file")
        }
        let cmode: CInt
        switch mode {
            case "no": cmode = _IONBF
            case "full": cmode = _IOFBF
            case "line": cmode = _IOLBF
            default: throw await Lua.error(in: state, message: "bad argument #1 (invalid option '\(mode)')")
        }
        LibC.setvbuf(handle, nil, cmode, size ?? Int(BUFSIZ))
    }

    public func seek(_ state: Lua, whence: String?, offset: Int?) async throws -> Int {
        guard let handle = handle else {
            throw await Lua.error(in: state, message: "attempt to use a closed file")
        }
        let whence = whence ?? "cur"
        let offset = offset ?? 0
        let cwhence: CInt
        switch whence {
            case "cur": cwhence = SEEK_CUR
            case "set": cwhence = SEEK_SET
            case "end": cwhence = SEEK_END
            default: throw await Lua.error(in: state, message: "bad argument #1 (invalid option '\(whence)')")
        }
        fseek(handle, offset, cwhence) // TODO: error check
        return ftell(handle)
    }

    public func write(_ state: Lua, _ args: LuaArgs) async throws -> [LuaValue] {
        guard let handle = handle else {
            throw await Lua.error(in: state, message: "attempt to use a closed file")
        }
        if args.count == 0 {
            return [.object(self)]
        }
        for i in 1...args.count {
            let str = await args[i].toString
            if fwrite(str, str.count, 1, handle) < str.count {
                return [.nil, .string(.string(String(cString: strerror(errno_()))))]
            }
        }
        return [.object(self)]
    }

    internal func isOpen() -> Bool {
        return handle != nil
    }

    init(_ h: FileDescriptor) {
        handle = h
    }
}

@LuaLibrary(named: "io")
internal actor IOLibrary {
    public static let stdin = FileObject(LibC.stdin_())
    public static let stdout = FileObject(LibC.stdout_())
    public static let stderr = FileObject(LibC.stderr_())

    private var inputHandle = stdin
    private var outputHandle = stdout

    public func close(_ state: Lua, file: LuaValue?) async throws {
        if let file = file {
            let handle = try file.checkUserdata(at: 1, as: FileObject.self)
            try await handle.close(state)
        } else {
            try await outputHandle.close(state)
        }
    }

    public func flush(_ state: Lua) async throws {
        try await outputHandle.flush(state)
    }

    public func input(_ state: Lua, file: LuaValue?) async throws -> LuaValue {
        if let file = file {
            var handle: FileObject!
            if case let .string(path) = file {
                if let h = fopen(path.string, "r") {
                    handle = FileObject(h)
                } else {
                    throw await Lua.error(in: state, message: String(cString: strerror(errno_())))
                }
            } else {
                handle = try file.checkUserdata(at: 1, as: FileObject.self)
            }
            inputHandle = handle
        }
        return .object(inputHandle)
    }

    public func lines(_ state: Lua, args: LuaArgs) async throws -> LuaValue {
        if args.count == 0 {
            return await inputHandle.lines(state, LuaArgs([], state: state))
        }
        if let fp = fopen(try await args.checkString(at: 1), "r") {
            let handle = FileObject(fp)
            return .function(.swift(LuaSwiftFunction {_state, _args in
                if await !handle.isOpen() {
                    return []
                }
                if args.count == 0 {
                    let v = try await handle.read(mode: .string(.string("l")), state: _state)
                    if v == .nil {
                        try await handle.close(_state)
                    }
                    return [v]
                }
                var retval = [LuaValue]()
                var close = false
                for i in 1...args.count {
                    let v = try await handle.read(mode: args[i], state: _state)
                    if v == .nil {
                        close = true
                    }
                    retval.append(v)
                }
                if close {
                    try await handle.close(_state)
                }
                return retval
            }))
        } else {
            throw await Lua.error(in: state, message: String(cString: strerror(errno_())))
        }
    }

    public func open(path: String, mode: String?) -> [LuaValue] {
        if let fp = fopen(path, mode ?? "r") {
            return [.object(FileObject(fp))]
        } else {
            return [.nil, .string(.string(String(cString: strerror(errno_()))))]
        }
    }

    public func output(_ state: Lua, file: LuaValue?) async throws -> LuaValue {
        if let file = file {
            var handle: FileObject!
            if case let .string(path) = file {
                do {
                    let h = try path.string.withCString {_path in
                        if let h = fopen(_path, "w") {
                            return h
                        } else {
                            throw Lua.LuaError.runtimeError(message: String(cString: strerror(errno_())))
                        }
                    }
                    handle = FileObject(h)
                } catch let error as Lua.LuaError {
                    if case let .runtimeError(str) = error {
                        throw await Lua.error(in: state, message: str)
                    } else {
                        throw error
                    }
                }
            } else {
                handle = try file.checkUserdata(at: 1, as: FileObject.self)
            }
            outputHandle = handle
        }
        return .object(outputHandle)
    }

    public func popen(_ state: Lua, path: String, mode: String?) throws -> [LuaValue] {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return [.nil, .string(.string("popen not available on this platform"))]
        #else
        if let fp = LibC.popen_(path, mode ?? "r") {
            return [.object(FileObject(fp))]
        } else {
            return [.nil, .string(.string(String(cString: strerror(errno_()))))]
        }
        #endif
    }

    public func read(_ state: Lua, _ args: LuaArgs) async throws -> [LuaValue] {
        return try await inputHandle.read(state, args)
    }

    public func tmpfile() -> LuaValue {
        return .object(FileObject(LibC.tmpfile()))
    }

    public func type(value: LuaValue) async -> String? {
        do {
            let handle = try value.checkUserdata(at: 1, as: FileObject.self)
            if await handle.isOpen() {
                return "file"
            } else {
                return "closed file"
            }
        } catch {
            return nil
        }
    }

    public func write(_ state: Lua, _ args: LuaArgs) async throws -> [LuaValue] {
        return try await outputHandle.write(state, args)
    }
}
