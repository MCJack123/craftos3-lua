import Lua
import Math

fileprivate struct JavaRandomNumberGenerator: RandomNumberGenerator {
    private var state = 0
    public mutating func seed(_ val: Int) {
        state = (val ^ 0x5DEECE66D) & 0xFFFFFFFFFFFF
    }
    public mutating func next() -> UInt64 {
        state = (state * 0x5DEECE66D) & 0xFFFFFFFFFFFF
        return UInt64(state) << 16
    }
}

internal class MathLibrary: LuaLibrary {
    public let name = "math"
    private var rng = JavaRandomNumberGenerator()

    public let abs = LuaSwiftFunction {state, args in [.number(Swift.abs(try args.checkNumber(at: 1)))]}
    public let acos = LuaSwiftFunction {state, args in [.number(Math.acos(try args.checkNumber(at: 1)))]}
    public let asin = LuaSwiftFunction {state, args in [.number(Math.asin(try args.checkNumber(at: 1)))]}
    public let atan = LuaSwiftFunction {state, args in [.number(Math.atan(try args.checkNumber(at: 1)))]}
    public let atan2 = LuaSwiftFunction {state, args in [.number(Math.atan2(try args.checkNumber(at: 1), try args.checkNumber(at: 2)))]}
    public let ceil = LuaSwiftFunction {state, args in [.number(Math.ceil(try args.checkNumber(at: 1)))]}
    public let cos = LuaSwiftFunction {state, args in [.number(Math.cos(try args.checkNumber(at: 1)))]}
    public let cosh = LuaSwiftFunction {state, args in [.number(Math.cosh(try args.checkNumber(at: 1)))]}
    public let deg = LuaSwiftFunction {state, args in [.number(try args.checkNumber(at: 1) * (180.0 / Double.pi))]}
    public let exp = LuaSwiftFunction {state, args in [.number(Math.exp(try args.checkNumber(at: 1)))]}
    public let floor = LuaSwiftFunction {state, args in [.number(Math.floor(try args.checkNumber(at: 1)))]}
    public let fmod = LuaSwiftFunction {state, args in [.number(Math.fmod(try args.checkNumber(at: 1), try args.checkNumber(at: 2)))]}
    public let ldexp = LuaSwiftFunction {state, args in [.number(Math.ldexp(try args.checkNumber(at: 1), Int32(try args.checkInt(at: 2))))]}
    public let pow = LuaSwiftFunction {state, args in [.number(Math.pow(try args.checkNumber(at: 1), try args.checkNumber(at: 2)))]}
    public let rad = LuaSwiftFunction {state, args in [.number(try args.checkNumber(at: 1) * (Double.pi / 180.0))]}
    public let sin = LuaSwiftFunction {state, args in [.number(Math.sin(try args.checkNumber(at: 1)))]}
    public let sinh = LuaSwiftFunction {state, args in [.number(Math.sinh(try args.checkNumber(at: 1)))]}
    public let sqrt = LuaSwiftFunction {state, args in [.number(Math.sqrt(try args.checkNumber(at: 1)))]}
    public let tan = LuaSwiftFunction {state, args in [.number(Math.tan(try args.checkNumber(at: 1)))]}
    public let tanh = LuaSwiftFunction {state, args in [.number(Math.tanh(try args.checkNumber(at: 1)))]}

    public let huge = LuaValue.number(Double.infinity)
    public let pi = LuaValue.number(Double.pi)

    public let frexp = LuaSwiftFunction {state, args in
        var e = CInt(0)
        var m = Double(0)
        try withUnsafeMutablePointer(to: &e) { _e in
            m = Math.frexp(try args.checkNumber(at: 1), _e)
        }
        return [.number(m), .number(Double(e))]
    }
    public let log = LuaSwiftFunction {state, args in
        [.number(Math.log(try args.checkNumber(at: 1)) / Math.log(try args.checkNumber(at: 2, default: Math.exp(1))))]
    }
    public let modf = LuaSwiftFunction {state, args in
        var d = Double(0)
        var i = Double(0)
        try withUnsafeMutablePointer(to: &d) { _d in
            i = Math.modf(try args.checkNumber(at: 1), _d)
        }
        return [.number(i), .number(d)]
    }
    public let min = LuaSwiftFunction {state, args in
        _=try args.checkNumber(at: 1)
        var n = Double.infinity
        for i in 1...args.count {
            n = Swift.min(n, try args.checkNumber(at: i))
        }
        return [.number(n)]
    }
    public let max = LuaSwiftFunction {state, args in
        _=try args.checkNumber(at: 1)
        var n = -Double.infinity
        for i in 1...args.count {
            n = Swift.max(n, try args.checkNumber(at: i))
        }
        return [.number(n)]
    }

    public var random = LuaSwiftFunction {state, args in []} 
    public var randomseed = LuaSwiftFunction {state, args in []} 
    private func _random(_ state: Lua, _ args: LuaArgs) async throws -> [LuaValue] {
        if let max = try? args.checkInt(at: 2) {
            let min = try args.checkInt(at: 1)
            return [.number(Double(Int.random(in: min...max, using: &rng)))]
        } else if let max = try? args.checkInt(at: 1) {
            return [.number(Double(Int.random(in: 0...max, using: &rng)))]
        } else {
            return [.number(Double.random(in: 0..<1, using: &rng))]
        }
    }
    private func _randomseed(_ state: Lua, _ args: LuaArgs) async throws -> [LuaValue] {
        rng.seed(try args.checkInt(at: 1))
        return []
    }

    public init() {
        random = LuaSwiftFunction(from: _random)
        randomseed = LuaSwiftFunction(from: _randomseed)
    }
}