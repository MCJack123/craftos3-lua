public extension String {
    var trimmingSpaces: Substring {
        var index = startIndex
        while index < endIndex && self[index].isWhitespace {
            index = self.index(after: index)
        }
        if index == endIndex {
            return Substring()
        }
        var eindex = self.index(before: endIndex)
        while eindex > index && self[eindex].isWhitespace {
            eindex = self.index(before: eindex)
        }
        return self[index...eindex]
    }

    var bytes: [UInt8] {
        return self.map {UInt8(exactly: $0.unicodeScalars.first?.value ?? 0) ?? 0}
    }
}

extension Array: @retroactive ExpressibleByExtendedGraphemeClusterLiteral, @retroactive ExpressibleByUnicodeScalarLiteral, @retroactive ExpressibleByStringLiteral, @retroactive ExpressibleByStringInterpolation where Element == UInt8 {
    public typealias StringLiteralType = String

    public init(stringLiteral: Self.StringLiteralType) {
        self.init(stringLiteral.map {UInt8(exactly: $0.unicodeScalars.first?.value ?? 0) ?? 0})
    }

    public var string: String {
        return String(self.map {Character(Unicode.Scalar($0))})
    }
}

public extension Array where Element: Equatable {
    func count(of el: Element) -> Int {
        var c = 0
        for e in self {
            if e == el {
                c += 1
            }
        }
        return c
    }
}

extension UInt8: @retroactive ExpressibleByExtendedGraphemeClusterLiteral, @retroactive ExpressibleByUnicodeScalarLiteral, @retroactive ExpressibleByStringLiteral, @retroactive ExpressibleByStringInterpolation {
    public typealias StringLiteralType = String

    public init(stringLiteral: Self.StringLiteralType) {
        self.init(stringLiteral.unicodeScalars.first?.value ?? 0)
    }
}

public enum LuaString: Hashable, Sendable, Comparable, CustomStringConvertible {
    case string([UInt8])
    case substring(ArraySlice<UInt8>)
    indirect case rope(LuaString, LuaString)

    public var string: String {
        switch self {
            case .string(let val): return val.string
            case .substring(let val): return [UInt8](val).string
            case .rope(let a, let b): return a.string + b.string
        }
    }

    public var bytes: [UInt8] {
        switch self {
            case .string(let val): return val
            case .substring(let val): return [UInt8](val)
            case .rope(let a, let b): return a.bytes + b.bytes
        }
    }

    public static func string(_ str: String) -> LuaString {
        return .string(str.map {
            if let val = $0.unicodeScalars.first?.value, val < 256 {UInt8(val)} else {0}
        })
    }

    public static func == (lhs: LuaString, rhs: LuaString) -> Bool {
        return lhs.bytes == rhs.bytes
    }

    public static func < (lhs: LuaString, rhs: LuaString) -> Bool {
        return lhs.string < rhs.string
    }

    public static func <= (lhs: LuaString, rhs: LuaString) -> Bool {
        return lhs.string <= rhs.string
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bytes)
    }

    public var description: String {
        return string
    }
}