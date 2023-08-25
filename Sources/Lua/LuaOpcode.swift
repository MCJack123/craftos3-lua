internal enum LuaOpcode {
    enum Operation: UInt8 {
        case MOVE = 0
        case LOADK = 1
        case LOADBOOL = 2
        case LOADNIL = 3
        case GETUPVAL = 4
        case GETGLOBAL = 5
        case GETTABLE = 6
        case SETGLOBAL = 7
        case SETUPVAL = 8
        case SETTABLE = 9
        case NEWTABLE = 10
        case SELF = 11
        case ADD = 12
        case SUB = 13
        case MUL = 14
        case DIV = 15
        case MOD = 16
        case POW = 17
        case UNM = 18
        case NOT = 19
        case LEN = 20
        case CONCAT = 21
        case JMP = 22
        case EQ = 23
        case LT = 24
        case LE = 25
        case TEST = 26
        case TESTSET = 27
        case CALL = 28
        case TAILCALL = 29
        case RETURN = 30
        case FORLOOP = 31
        case FORPREP = 32
        case TFORLOOP = 33
        case SETLIST = 34
        case CLOSE = 35
        case CLOSURE = 36
        case VARARG = 37
    }

    case iABC(Operation, UInt8, UInt16, UInt16)
    case iABx(Operation, UInt8, UInt32)
    case iAsBx(Operation, UInt8, Int32)

    internal static func decode(_ op: UInt32) -> LuaOpcode? {
        if let opcode = Operation(rawValue: UInt8(op & 0x3F)) {
            let a = UInt8((op >> 6) & 0xFF)
            switch opcode {
                case .MOVE, .LOADBOOL, .LOADNIL, .GETUPVAL, .GETTABLE, .SETUPVAL,
                     .SETTABLE, .NEWTABLE, .SELF, .ADD, .SUB, .MUL, .DIV, .MOD,
                     .POW, .UNM, .NOT, .LEN, .CONCAT, .EQ, .LT, .LE, .TEST,
                     .TESTSET, .CALL, .TAILCALL, .RETURN, .TFORLOOP, .SETLIST,
                     .CLOSE, .VARARG:
                    let b = (op >> 23) & 0x1FF
                    let c = (op >> 14) & 0x1FF
                    return .iABC(opcode, a, UInt16(b), UInt16(c))
                case .LOADK, .GETGLOBAL, .SETGLOBAL, .CLOSURE:
                    let bx  = (op >> 14) & 0x3FFFF
                    return .iABx(opcode, a, bx)
                case .JMP, .FORLOOP, .FORPREP:
                    let sbx = Int32((op >> 14) & 0x3FFFF) - 131071
                    return .iAsBx(opcode, a, sbx)
            }
        } else {
            return nil
        }
    }

    internal var encoded: UInt32 {
        switch self {
            case .iABC(let op, let a, let b, let c):
                return UInt32(op.rawValue) | (UInt32(a) << 6) | (UInt32(c) << 14) | (UInt32(b) << 23)
            case .iABx(let op, let a, let bx):
                return UInt32(op.rawValue) | (UInt32(a) << 6) | (UInt32(bx) << 14)
            case .iAsBx(let op, let a, let sbx):
                return UInt32(op.rawValue) | (UInt32(a) << 6) | (UInt32(sbx + 131071) << 14)
        }
    }
}