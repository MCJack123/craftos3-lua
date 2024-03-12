public enum LuaOpcode: Equatable {
    public enum Operation: UInt8 {
        case MOVE = 0
        case LOADK = 1
        case LOADKX = 2
        case LOADBOOL = 3
        case LOADNIL = 4
        case GETUPVAL = 5
        case GETTABUP = 6
        case GETTABLE = 7
        case SETTABUP = 8
        case SETUPVAL = 9
        case SETTABLE = 10
        case NEWTABLE = 11
        case SELF = 12
        case ADD = 13
        case SUB = 14
        case MUL = 15
        case DIV = 16
        case MOD = 17
        case POW = 18
        case UNM = 19
        case NOT = 20
        case LEN = 21
        case CONCAT = 22
        case JMP = 23
        case EQ = 24
        case LT = 25
        case LE = 26
        case TEST = 27
        case TESTSET = 28
        case CALL = 29
        case TAILCALL = 30
        case RETURN = 31
        case FORLOOP = 32
        case FORPREP = 33
        case TFORCALL = 34
        case TFORLOOP = 35
        case SETLIST = 36
        case CLOSURE = 37
        case VARARG = 38
        case EXTRAARG = 39
    }

    case iABC(Operation, UInt8, UInt16, UInt16)
    case iABx(Operation, UInt8, UInt32)
    case iAsBx(Operation, UInt8, Int32)
    case iAx(Operation, UInt32)

    internal static func decode(_ op: UInt32) -> LuaOpcode? {
        if let opcode = Operation(rawValue: UInt8(op & 0x3F)) {
            let a = UInt8((op >> 6) & 0xFF)
            switch opcode {
                case .MOVE, .LOADBOOL, .LOADNIL, .GETUPVAL, .GETTABLE, .SETUPVAL,
                     .SETTABLE, .NEWTABLE, .SELF, .ADD, .SUB, .MUL, .DIV, .MOD,
                     .POW, .UNM, .NOT, .LEN, .CONCAT, .EQ, .LT, .LE, .TEST,
                     .TESTSET, .CALL, .TAILCALL, .RETURN, .SETLIST, .LOADKX,
                     .VARARG, .GETTABUP, .SETTABUP, .TFORCALL:
                    let b = (op >> 23) & 0x1FF
                    let c = (op >> 14) & 0x1FF
                    return .iABC(opcode, a, UInt16(b), UInt16(c))
                case .LOADK, .CLOSURE:
                    let bx  = (op >> 14) & 0x3FFFF
                    return .iABx(opcode, a, bx)
                case .JMP, .FORLOOP, .FORPREP, .TFORLOOP:
                    let sbx = Int32((op >> 14) & 0x3FFFF) - 131071
                    return .iAsBx(opcode, a, sbx)
                case .EXTRAARG:
                    let ax = UInt32(op >> 6)
                    return .iAx(opcode, ax)
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
            case .iAx(let op, let ax):
                return UInt32(op.rawValue) | (ax << 6)
        }
    }
}