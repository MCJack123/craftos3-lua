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

public class LuaInterpretedFunction: Hashable {
    internal let opcodes: [LuaOpcode]
    internal let constants: [LuaValue]
    internal let prototypes: [LuaInterpretedFunction]
    internal let stackSize: UInt8
    internal let numUpvalues: UInt8
    internal let numParams: UInt8
    internal let isVararg: UInt8
    internal let name: String
    internal let lineDefined: Int32
    internal let lastLineDefined: Int32
    internal let lineinfo: [Int32]
    internal let locals: [(String, Int32, Int32)]
    internal let upvalueNames: [String]

    public enum DecodeError: Error {
        case invalidBytecode
    }

    public convenience init(decoding data: UnsafeRawBufferPointer) throws {
        if !data.prefix(12).elementsEqual([0x1B, 0x4C, 0x75, 0x61, 0x51, 0x00, 0x01, 0x04, 0x04, 0x04, 0x08, 0x00]) {
            throw DecodeError.invalidBytecode
        }
        var pos = 12
        try self.init(data: data, pos: &pos)
    }

    private init(data: UnsafeRawBufferPointer, pos: inout Int) throws {
        name = readString(data, &pos)
        lineDefined = data.loadUnaligned(fromByteOffset: pos, as: Int32.self)
        lastLineDefined = data.loadUnaligned(fromByteOffset: pos + 4, as: Int32.self)
        numUpvalues = data[pos + 8]
        numParams = data[pos + 9]
        isVararg = data[pos + 10]
        stackSize = data[pos + 11]
        pos += 12
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
        lineinfo = readList(data, &pos) {_data, _pos in
            defer {_pos += 4}
            return _data.loadUnaligned(fromByteOffset: _pos, as: Int32.self)
        }
        locals = readList(data, &pos) {_data, _pos in
            let str = readString(_data, &_pos)
            defer {_pos += 8}
            return (str, _data.loadUnaligned(fromByteOffset: _pos, as: Int32.self), _data.loadUnaligned(fromByteOffset: _pos + 4, as: Int32.self))
        }
        upvalueNames = readList(data, &pos) {_data, _pos in
            return readString(_data, &_pos)
        }
    }

    public static func == (lhs: LuaInterpretedFunction, rhs: LuaInterpretedFunction) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(self).toOpaque())
    }
}