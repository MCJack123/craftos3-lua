import Lua
import Foundation

internal class OSLibrary: LuaLibrary {
    public let name = "os"
    private var locale = Locale.current

    public let clock = LuaSwiftFunction {state, args in
        return [.number(Double(Foundation.clock()))]
    }

    // public let date = LuaSwiftFunction {state, args in
    //     let format =
    // }

    public let difftime = LuaSwiftFunction {state, args in
        return [.number(Double(Foundation.difftime(time_t(try args.checkInt(at: 1)), time_t(try args.checkInt(at: 2)))))]
    }

    public let execute = LuaSwiftFunction {state, args in
        var shellPath: String? = nil
        var arguments = [String]()
        #if os(macOS) || os(Linux)
        shellPath = "/bin/sh"
        arguments.append("-c")
        #elseif os(Windows)
        shellPath = "\(String(cString: Foundation.getenv("SYSTEM32")))\\cmd.exe"
        arguments.append("/c")
        #endif
        if args.count == 0 {
            return [.boolean(shellPath != nil)]
        }
        arguments.append(try args.checkString(at: 1))
        if let shellPath = shellPath {
            let process = try Process.run(URL(fileURLWithPath: shellPath), arguments: arguments)
            process.waitUntilExit()
            switch process.terminationReason {
                case .exit:
                    if process.terminationStatus == 0 {
                        return [.boolean(true), .string(.string("exit")), .number(0)]
                    }
                    return [.nil, .string(.string("exit")), .number(Double(process.terminationStatus))]
                case .uncaughtSignal:
                    return [.nil, .string(.string("signal")), .number(Double(process.terminationStatus))]
                @unknown default: return [.nil]
            }
        }
        return [.nil, .string(.string("exit")), .number(127)]
    }

    public let exit = LuaSwiftFunction {state, args in
        switch args[1] {
            case .nil: Foundation.exit(0)
            case .boolean(let b): Foundation.exit(b ? 1 : 0)
            case .number(let n): Foundation.exit(Int32(n))
            default: throw state.argumentError(at: 1, for: args[1], expected: "boolean or number")
        }
    }

    public let getenv = LuaSwiftFunction {state, args in
        return try args.checkString(at: 1).withCString {_str in
            return [.string(.string(String(cString: Foundation.getenv(_str))))]
        }
    }

    public let remove = LuaSwiftFunction {state, args in
        do {
            try FileManager.default.removeItem(atPath: try args.checkString(at: 1))
        } catch let error as CocoaError {
            return [.nil, .string(.string(error.localizedDescription)), .number(Double(error.errorCode))]
        } catch let error {
            return [.nil, .string(.string(error.localizedDescription))]
        }
        return [.boolean(true)]
    }

    public let rename = LuaSwiftFunction {state, args in
        do {
            try FileManager.default.moveItem(atPath: try args.checkString(at: 1), toPath: try args.checkString(at: 2))
        } catch let error as CocoaError {
            return [.nil, .string(.string(error.localizedDescription)), .number(Double(error.errorCode))]
        } catch let error {
            return [.nil, .string(.string(error.localizedDescription))]
        }
        return [.boolean(true)]
    }

    public var setlocale = LuaSwiftFunction.empty
    private func _setlocale(_ state: Lua, _ args: LuaArgs) async throws -> [LuaValue] {
        let locnam = try args.checkString(at: 1, default: "")
        let category = try args.checkString(at: 2, default: "all")
        if category == "all" {
            if args[1] == .nil {
                return [.string(.string(locale.identifier))]
            }
            locale = Locale(identifier: locnam)
            return []
        }
        #if !(os(Linux) || os(Windows))
        /*if #available(macOS 13, iOS 16, tvOS 16, watchOS 9, *) {
            let components = Locale.Components(locale: locale)
            switch category {
                case "collate":
                    if args[1] == .nil {
                        return [.string(.string(components.collation.identifier))]
                    }
                    components.collation = Locale.Collation(locnam)
                case "ctype":
                    if args[1] == .nil {
                        return [.string(.string(components.languageComponents.script.identifier))]
                    }
                    components.languageComponents.script = Locale.Script(locnam)
                case "monetary":
                    if args[1] == .nil {
                        return [.string(.string(components.currency.identifier))]
                    }
                    components.currency = Locale.Currency(locnam)
                case "numeric":
                    if args[1] == .nil {
                        return [.string(.string(components.numberingSystem.identifier))]
                    }
                    components.numberingSystem = Locale.NumberingSystem(locnam)
                case "time":
                    // ?
                    break
                default: throw Lua.error(in: state, message: "bad argument #2 (invalid category)")
            }
            return []
        }*/
        #endif
        // ?
        return []
    }

    public let time = LuaSwiftFunction {state, args in
        if case let .table(t) = args[1] {
            guard case let .number(year) = t["year"] else {
                throw Lua.error(in: state, message: "bad argument #1 (bad field 'year')")
            }
            guard case let .number(month) = t["month"] else {
                throw Lua.error(in: state, message: "bad argument #1 (bad field 'month')")
            }
            guard case let .number(day) = t["day"] else {
                throw Lua.error(in: state, message: "bad argument #1 (bad field 'day')")
            }
            guard case let .number(hour) = t["hour"].orElse(.number(12)) else {
                throw Lua.error(in: state, message: "bad argument #1 (bad field 'hour')")
            }
            guard case let .number(min) = t["min"].orElse(.number(0)) else {
                throw Lua.error(in: state, message: "bad argument #1 (bad field 'min')")
            }
            guard case let .number(sec) = t["sec"].orElse(.number(0)) else {
                throw Lua.error(in: state, message: "bad argument #1 (bad field 'sec')")
            }
            var date = DateComponents()
            date.year = Int(year)
            date.month = Int(month)
            date.day = Int(day)
            date.hour = Int(hour)
            date.minute = Int(min)
            date.second = Int(sec)
            //date.timeZone = t["isdst"].toBool ? TimeZone(secondsFromGMT: TimeZone.current.) : .current
            return [.number(Double(Calendar.current.date(from: date)?.timeIntervalSince1970 ?? 0))]
        }
        return [.number(Double(Date().timeIntervalSince1970))]
    }

    public let tmpname = LuaSwiftFunction {state, args in
        #if os(Windows) || os(Linux)
        return [.string(.string(String(cString: Foundation.tmpnam(UnsafeMutablePointer<CChar>(bitPattern: 0)))))]
        #else
        return [.string(.string(""))]
        #endif
    }

    public init() {
        setlocale = LuaSwiftFunction(from: _setlocale)
    }
}
