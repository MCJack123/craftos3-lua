private func readString(_ data: UnsafeRawBufferPointer, _ pos: inout Int) -> String {
    let size = data.loadUnaligned(fromByteOffset: pos, as: UInt32.self)
    var str = String(data[(pos + 4) ..< (pos + 4 + Int(size))].map {Character(Unicode.Scalar($0))})
    if size > 0 {str.removeLast()}
    pos += Int(size) + 4
    return str
}

private func readList<T>(_ data: UnsafeRawBufferPointer, _ pos: inout Int, _ body: (UnsafeRawBufferPointer, inout Int) throws -> T) rethrows -> [T] {
    let size = data.loadUnaligned(fromByteOffset: pos, as: UInt32.self)
    pos += 4
    var arr = [T]()
    for _ in 0..<Int(size) {
        arr.append(try body(data, &pos))
    }
    return arr
}

private enum DumpValue {
    case byte(UInt8)
    case int(Int32)
    case instruction(LuaOpcode)
    case number(Double)
    case string(String)

    var size: Int {
        switch self {
            case .byte: return 1
            case .int, .instruction: return 4
            case .number: return 8
            case .string(let str): return 5 + str.count
        }
    }

    func write(to buf: UnsafeMutableRawBufferPointer, at pos: Int) -> Int {
        switch self {
            case .byte(let val):
                buf.storeBytes(of: val, toByteOffset: pos, as: UInt8.self)
                return pos + 1
            case .int(let val):
                buf.storeBytes(of: val.littleEndian, toByteOffset: pos, as: Int32.self)
                return pos + 4
            case .instruction(let val):
                buf.storeBytes(of: val.encoded, toByteOffset: pos, as: UInt32.self)
                return pos + 4
            case .number(let val):
                buf.storeBytes(of: val, toByteOffset: pos, as: Double.self)
                return pos + 8
            case .string(let val):
                let size = UInt32(val.count + 1).littleEndian
                buf.storeBytes(of: size, toByteOffset: pos, as: UInt32.self)
                let s = val.map {c in
                    let ord = c.unicodeScalars.first!.value
                    if ord > 256 {return UInt8(63)}
                    else {return UInt8(ord)}
                }
                UnsafeMutableRawBufferPointer(rebasing: buf[(pos+4)..<(pos+4+Int(size))]).copyBytes(from: s)
                return pos + Int(size) + 4
        }
    }
}

public class LuaInterpretedFunction: Hashable {
    internal let opcodes: [LuaOpcode]
    internal let constants: [LuaValue]
    internal let prototypes: [LuaInterpretedFunction]
    internal let upvalues: [(UInt8, UInt8, String?)] // instack, idx, name
    internal let stackSize: UInt8
    internal let numParams: UInt8
    internal let isVararg: UInt8
    internal let name: [UInt8]
    internal let lineDefined: Int32
    internal let lastLineDefined: Int32
    internal let lineinfo: [Int32]
    internal let locals: [(String, Int32, Int32)]

    public enum DecodeError: Error {
        case invalidBytecode
    }

    public var upvalueNames: [String?] {
        return upvalues.map {$0.2}
    }

    public init(
        opcodes: [LuaOpcode],
        constants: [LuaValue],
        prototypes: [LuaInterpretedFunction],
        upvalues: [(UInt8, UInt8, String?)],
        stackSize: UInt8,
        numParams: UInt8,
        isVararg: UInt8,
        name: [UInt8],
        lineDefined: Int32,
        lastLineDefined: Int32,
        lineinfo: [Int32],
        locals: [(String, Int32, Int32)]
    ) {
        self.opcodes = opcodes
        self.constants = constants
        self.prototypes = prototypes
        self.upvalues = upvalues
        self.stackSize = stackSize
        self.numParams = numParams
        self.isVararg = isVararg
        self.name = name
        self.lineDefined = lineDefined
        self.lastLineDefined = lastLineDefined
        self.lineinfo = lineinfo
        self.locals = locals
    }

    public convenience init(decoding data: UnsafeRawBufferPointer, named name: [UInt8]? = nil) throws {
        if !data.prefix(18).elementsEqual([0x1B, 0x4C, 0x75, 0x61, 0x52, 0x00, 0x01, 0x04, 0x04, 0x04, 0x08, 0x00, 0x19, 0x93, 0x0D, 0x0A, 0x1A, 0x0A]) {
            throw DecodeError.invalidBytecode
        }
        var pos = 18
        try self.init(data: data, pos: &pos, name: name)
    }

    private init(data: UnsafeRawBufferPointer, pos: inout Int, name: [UInt8]? = nil) throws {
        lineDefined = data.loadUnaligned(fromByteOffset: pos, as: Int32.self)
        lastLineDefined = data.loadUnaligned(fromByteOffset: pos + 4, as: Int32.self)
        numParams = data[pos + 8]
        isVararg = data[pos + 9]
        stackSize = data[pos + 10]
        pos += 11
        opcodes = try readList(data, &pos) {_data, _pos in
            let n = data.loadUnaligned(fromByteOffset: _pos, as: UInt32.self)
            _pos += 4
            if let op = LuaOpcode.decode(n) {
                return op
            } else {
                throw DecodeError.invalidBytecode
            }
        }
        constants = try readList(data, &pos) {_data, _pos in
            let type = _data[_pos]
            _pos += 1
            switch type {
                case 0:
                    return .nil
                case 1:
                    defer {_pos += 1}
                    return .boolean(_data[_pos] != 0)
                case 3:
                    defer {_pos += 8}
                    return .number(_data.loadUnaligned(fromByteOffset: _pos, as: Double.self))
                case 4:
                    return .string(.string(readString(_data, &_pos)))
                default: throw DecodeError.invalidBytecode
            }
        }
        prototypes = try readList(data, &pos) {_data, _pos in
            return try LuaInterpretedFunction(data: _data, pos: &_pos)
        }
        var _upvalues = readList(data, &pos) {_data, _pos in
            let retval: (UInt8, UInt8, String?) = (_data[_pos], _data[_pos+1], nil)
            _pos += 2
            return retval
        }
        let filename = readString(data, &pos)
        self.name = name ?? filename.bytes
        lineinfo = readList(data, &pos) {_data, _pos in
            defer {_pos += 4}
            return _data.loadUnaligned(fromByteOffset: _pos, as: Int32.self)
        }
        locals = readList(data, &pos) {_data, _pos in
            let str = readString(_data, &_pos)
            defer {_pos += 8}
            return (str, _data.loadUnaligned(fromByteOffset: _pos, as: Int32.self), _data.loadUnaligned(fromByteOffset: _pos + 4, as: Int32.self))
        }
        let upvalueNames = readList(data, &pos) {_data, _pos in
            return readString(_data, &_pos)
        }
        for (i, v) in upvalueNames.enumerated() {
            _upvalues[i].2 = v
        }
        upvalues = _upvalues
    }

    public func dump() -> [UInt8] {
        var output = [0x1B, 0x4C, 0x75, 0x61, 0x52, 0x00, 0x01, 0x04, 0x04, 0x04, 0x08, 0x00, 0x19, 0x93, 0x0D, 0x0A, 0x1A, 0x0A].map {DumpValue.byte($0)}
        output.append(contentsOf: dumpFunction())
        var size = 0
        for v in output {size += v.size}
        return [UInt8](unsafeUninitializedCapacity: size, initializingWith: {_buf, _size in
            let buf = UnsafeMutableRawBufferPointer(_buf)
            var pos = 0
            for v in output {
                pos = v.write(to: buf, at: pos)
            }
            _size = pos
        })
    }

    private func dumpFunction() -> [DumpValue] {
        var output: [DumpValue] = [.int(lineDefined), .int(lastLineDefined), .byte(numParams), .byte(isVararg), .byte(stackSize), .int(Int32(opcodes.count))]
        for op in opcodes {output.append(.instruction(op))}
        output.append(.int(Int32(constants.count)))
        for v in constants {
            switch v {
                case .nil:
                    output.append(.byte(0))
                case .boolean(let val):
                    output.append(.byte(1))
                    output.append(.byte(val ? 1 : 0))
                case .number(let val):
                    output.append(.byte(3))
                    output.append(.number(val))
                case .string(let val):
                    output.append(.byte(4))
                    output.append(.string(val.string))
                default:
                    assertionFailure("Invalid constant type in value \(v)")
            }
        }
        output.append(.int(Int32(prototypes.count)))
        for v in prototypes {output.append(contentsOf: v.dumpFunction())}
        output.append(.int(Int32(upvalues.count)))
        for v in upvalues {
            output.append(.byte(v.0))
            output.append(.byte(v.1))
        }
        output.append(.string(name.string))
        output.append(.int(Int32(lineinfo.count)))
        for v in lineinfo {output.append(.int(v))}
        output.append(.int(Int32(locals.count)))
        for v in locals {
            output.append(.string(v.0))
            output.append(.int(v.1))
            output.append(.int(v.2))
        }
        output.append(.int(Int32(upvalues.count)))
        for v in upvalues {output.append(.string(v.2 ?? ""))}
        return output
    }

    public static func == (lhs: LuaInterpretedFunction, rhs: LuaInterpretedFunction) -> Bool {
        return lhs.opcodes == rhs.opcodes &&
            lhs.constants == rhs.constants &&
            lhs.prototypes == rhs.prototypes &&
            lhs.upvalues.elementsEqual(rhs.upvalues) {$0 == $1} &&
            lhs.stackSize == rhs.stackSize &&
            lhs.numParams == rhs.numParams &&
            lhs.isVararg == rhs.isVararg &&
            lhs.name == rhs.name //&&
            //lhs.locals.elementsEqual(rhs.locals) {$0 == $1}
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(self).toOpaque())
    }
}