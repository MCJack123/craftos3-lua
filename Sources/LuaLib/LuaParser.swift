import Lua

internal struct LuaParser {
    private var lexer: LuaLexer
    private let coder: LuaCode
    private var tokens = [LuaLexer.Token]()
    private var current: LuaLexer.Token?
    private var saving = false

    internal enum Expression {
        case `nil`
        case `false`
        case `true`
        case vararg
        case constant(LuaValue)
        case function(Int)
        case prefixexp(PrefixExpression)
        case table([TableEntry])
        indirect case binop(LuaLexer.Operator, Expression, Expression)
        indirect case unop(LuaLexer.Operator, Expression)
    }

    internal enum PrefixExpression {
        case name(String)
        indirect case index(PrefixExpression, Expression)
        indirect case field(PrefixExpression, String)
        indirect case call(PrefixExpression, [Expression])
        indirect case callSelf(PrefixExpression, String, [Expression])
        indirect case paren(Expression)
    }

    internal enum TableEntry {
        case array(Expression)
        case field(String, Expression)
        case keyed(Expression, Expression)
    }

    internal enum Error: Swift.Error {
        case syntaxError(message: String, token: LuaLexer.Token?)
        case gotoError(message: String)
        case codeError(message: String)
    }

    private init(from lex: LuaLexer) async throws {
        lexer = lex
        coder = LuaCode(named: lex.name)
        _ = try await next()
    }

    private mutating func next() async throws {
        if !tokens.isEmpty && !saving {
            let tok = tokens.removeFirst()
            current = tok
            coder.line = tok.line
        } else {
            let tok = try await lexer.next()
            current = tok
            if let tok = tok {coder.line = tok.line}
            if saving, let tok = tok {
                tokens.append(tok)
            }
        }
    }

    private mutating func readName() async throws -> String {
        let tok = current
        guard case let .name(name, _) = tok else {
            if case let .keyword(kw, _) = tok, kw == .goto {
                return "goto"
            }
            throw Error.syntaxError(message: "name expected", token: tok)
        }
        try await next()
        return name
    }

    private mutating func readString() async throws -> [UInt8] {
        let tok = current
        guard case let .string(str, _) = tok else {
            throw Error.syntaxError(message: "string expected", token: tok)
        }
        try await next()
        return str
    }

    private mutating func readNumber() async throws -> Double {
        let tok = current
        guard case let .number(num, _) = tok else {
            throw Error.syntaxError(message: "number expected", token: tok)
        }
        try await next()
        return num
    }

    private mutating func consume(keyword w: LuaLexer.Keyword) async throws {
        guard case let .keyword(v, _) = current, v == w else {
            throw Error.syntaxError(message: "'\(w.rawValue)' expected", token: current)
        }
        try await next()
    }

    private mutating func consume(operator w: LuaLexer.Operator) async throws {
        guard case let .operator(v, _) = current, v == w else {
            throw Error.syntaxError(message: "'\(w.rawValue)' expected", token: current)
        }
        try await next()
    }

    private mutating func consume(constant w: LuaLexer.Constant) async throws {
        guard case let .constant(v, _) = current, v == w else {
            throw Error.syntaxError(message: "'\(w.rawValue)' expected", token: current)
        }
        try await next()
    }

    private mutating func block() async throws {
        while true {
            guard let tok = current else {
                return
            }
            switch tok {
                case .operator(let op, _):
                    switch op {
                        case .label:
                            try await next()
                            let name = try await readName()
                            try await consume(operator: .label)
                            try coder.label(named: name)
                        case .semicolon:
                            try await next()
                        case .lparen:
                            try await callorassign()
                        default: throw Error.syntaxError(message: "unexpected symbol", token: tok)
                    }
                case .keyword(let kw, _):
                    switch kw {
                        case .until, .end, .elseif, .else:
                            return
                        case .break:
                            try coder.break()
                            try await next()
                        case .goto:
                            try await next()
                            let name = try await readName()
                            try coder.goto(name)
                        case .do:
                            try await next()
                            coder.do()
                            try await block()
                            try await consume(keyword: .end)
                            try coder.end()
                        case .while:
                            try await next()
                            coder.while(try await exp())
                            try await consume(keyword: .do)
                            try await block()
                            try await consume(keyword: .end)
                            try coder.end()
                        case .repeat:
                            try await next()
                            coder.repeat()
                            try await block()
                            try await consume(keyword: .until)
                            coder.until(try await exp())
                        case .if:
                            try await next()
                            coder.if(try await exp())
                            try await consume(keyword: .then)
                            try await block()
                            ifloop: while true {
                                guard let tok = current else {
                                    throw Error.syntaxError(message: "'end' expected", token: current)
                                }
                                switch tok {
                                    case .keyword(let kw, _):
                                        switch kw {
                                            case .elseif:
                                                try await next()
                                                coder.elseif(try await exp())
                                                try await consume(keyword: .then)
                                                try await block()
                                            case .else:
                                                try await next()
                                                coder.else()
                                                try await block()
                                            case .end:
                                                try await next()
                                                try coder.end()
                                                break ifloop
                                            default:
                                                throw Error.syntaxError(message: "'end' expected", token: tok)
                                        }
                                    default:
                                        throw Error.syntaxError(message: "'end' expected", token: tok)
                                }
                            }
                        case .for:
                            saving = true
                            try await next()
                            try await next() // skip name for now
                            let tok = current
                            if case let .operator(op, _) = tok, op == .assign {
                                saving = false
                                try await next()
                                let name = try await readName()
                                try await next() // skip `=`
                                let start = try await exp()
                                try await consume(operator: .comma)
                                let stop = try await exp()
                                var step: Expression? = nil
                                if case let .operator(op, _) = current, op == .comma {
                                    try await next()
                                    step = try await exp()
                                }
                                try await consume(keyword: .do)
                                coder.forRange(named: name, start: start, stop: stop, step: step)
                                try await block()
                                try await consume(keyword: .end)
                                try coder.end()
                            } else {
                                if case let .operator(op, _) = tok, op == .comma {}
                                else if case let .keyword(kw, _) = tok, kw == .in {}
                                else {
                                    throw Error.syntaxError(message: "'=' or 'in' expected", token: tok)
                                }
                                saving = false
                                try await next()
                                var names = [try await readName()]
                                while case let .operator(op, _) = current, op == .comma {
                                    try await next()
                                    names.append(try await readName())
                                }
                                try await consume(keyword: .in)
                                var explist = [try await exp()]
                                while case let .operator(op, _) = current, op == .comma {
                                    try await next()
                                    explist.append(try await exp())
                                }
                                try await consume(keyword: .do)
                                coder.forIter(names: names, from: explist)
                                try await block()
                                try await consume(keyword: .end)
                                try coder.end()
                            }
                        case .function:
                            try await next()
                            var name = PrefixExpression.name(try await readName())
                            var isSelf = false
                            loopfunction: while true {
                                if case let .operator(op, _) = current {
                                    switch op {
                                        case .dot:
                                            try await next()
                                            name = .field(name, try await readName())
                                        case .colon:
                                            try await next()
                                            name = .field(name, try await readName())
                                            isSelf = true
                                            break loopfunction
                                        case .lparen:
                                            break loopfunction
                                        default: throw Error.syntaxError(message: "'(' expected", token: current)
                                    }
                                } else {
                                    throw Error.syntaxError(message: "'(' expected", token: current)
                                }
                            }
                            let idx = try await funcbody(addSelf: isSelf)
                            coder.assign(to: [name], from: [.function(idx)])
                        case .local:
                            try await next()
                            if case let .keyword(kw, _) = current, kw == .function {
                                try await next()
                                let name = try await readName()
                                _ = coder.local(named: name)
                                let idx = try await funcbody(addSelf: false)
                                coder.assign(to: [.name(name)], from: [.function(idx)])
                            } else {
                                var names = [try await readName()]
                                while case let .operator(op, _) = current, op == .comma {
                                    try await next()
                                    names.append(try await readName())
                                }
                                var values = [Expression]()
                                if case let .operator(op, _) = current, op == .assign {
                                    try await next()
                                    values.append(try await exp())
                                    while case let .operator(op, _) = current, op == .comma {
                                        try await next()
                                        values.append(try await exp())
                                    }
                                }
                                coder.local(named: names, values: values)
                            }
                        case .return:
                            try await next()
                            if current == nil {
                                coder.return([])
                                return
                            } else if case let .keyword(kw, _) = current, kw == .until || kw == .end || kw == .elseif || kw == .else {
                                coder.return([])
                                return
                            } else if case let .operator(op, _) = current, op == .label || op == .semicolon {
                                coder.return([])
                                if op == .semicolon {
                                    try await next()
                                    if current == nil {
                                        return
                                    } else if case let .keyword(kw, _) = current, kw == .until || kw == .end || kw == .elseif || kw == .else {
                                        return
                                    } else if case let .operator(op, _) = current, op == .label {
                                        return
                                    } else {
                                        throw Error.syntaxError(message: "'end' expected", token: current)
                                    }
                                }
                            } else {
                                var explist = [try await exp()]
                                while case let .operator(op, _) = current, op == .comma {
                                    try await next()
                                    explist.append(try await exp())
                                }
                                coder.return(explist)
                            }
                        default: throw Error.syntaxError(message: "unexpected symbol", token: tok)
                    }
                case .name:
                    try await callorassign()
                default: throw Error.syntaxError(message: "unexpected symbol", token: tok)
            }
        }
    }

    private mutating func brackets(start: LuaLexer.Operator, end: LuaLexer.Operator) async throws {
        var pc = 1
        while pc > 0 {
            try await next()
            if case let .operator(op, _) = current {
                if op == start {pc += 1}
                else if op == end {pc -= 1}
            }
        }
        try await next()
    }

    private mutating func callorassign() async throws {
        let start = try await prefixexp()
        switch start {
            case .call, .callSelf:
                coder.call(start)
                return
            case .paren: throw Error.syntaxError(message: "syntax error", token: current)
            default: break
        }
        var names = [start]
        while case let .operator(op, _) = current, op == .comma {
            try await next()
            let name = try await prefixexp()
            switch start {
                case .call, .callSelf, .paren: throw Error.syntaxError(message: "syntax error", token: current)
                default: break
            }
            names.append(name)
        }
        try await consume(operator: .assign)
        var explist = [try await exp()]
        while case let .operator(op, _) = current, op == .comma {
            try await next()
            explist.append(try await exp())
        }
        coder.assign(to: names, from: explist)
    }

    private mutating func args() async throws -> [Expression] {
        if case let .string(str, _) = current {
            try await next()
            return [.constant(.string(.string(str)))]
        } else if case let .operator(op, _) = current {
            if op == .lbrace {
                return [try await table()]
            } else if op == .lparen {
                try await next()
                if case let .operator(op, _) = current, op == .rparen {
                    try await next()
                    return []
                }
                var explist = [try await exp()]
                while case let .operator(op, _) = current, op == .comma {
                    try await next()
                    explist.append(try await exp())
                }
                try await consume(operator: .rparen)
                return explist
            } else {
                throw Error.syntaxError(message: "'(' expected", token: current)
            }
        } else {
            throw Error.syntaxError(message: "'(' expected", token: current)
        }
    }

    private mutating func prefixexp() async throws -> PrefixExpression {
        var retval: PrefixExpression
        let line = lexer.line
        defer {coder.line = line}
        if case let .operator(op, _) = current, op == .lparen {
            try await next()
            retval = .paren(try await exp())
            try await consume(operator: .rparen)
        } else if case let .name(name, _) = current {
            try await next()
            retval = .name(name)
        } else {
            throw Error.syntaxError(message: "name expected", token: current)
        }
        while true {
            switch current {
                case .operator(let op, _):
                    switch op {
                        case .dot:
                            try await next()
                            retval = .field(retval, try await readName())
                        case .lbracket:
                            try await next()
                            retval = .index(retval, try await exp())
                            try await consume(operator: .rbracket)
                        case .lparen, .lbrace:
                            retval = .call(retval, try await args())
                        case .colon:
                            try await next()
                            let name = try await readName()
                            retval = .callSelf(retval, name, try await args())
                        default: return retval
                    }
                case .string:
                    retval = .call(retval, try await args())
                default: return retval
            }
        }
    }

    private mutating func expitem() async throws -> Expression {
        switch current {
            case .constant(let k, _):
                try await next()
                switch k {
                    case .nil: return .nil
                    case .false: return .false
                    case .true: return .true
                    case .vararg: return .vararg
                }
            case .number(let n, _):
                try await next()
                return .constant(.number(n))
            case .string(let str, _):
                try await next()
                return .constant(.string(.string(str)))
            case .keyword(let kw, _):
                if kw == .function {
                    try await next()
                    return .function(try await funcbody(addSelf: false))
                } else {
                    throw Error.syntaxError(message: "unexpected symbol", token: current)
                }
            case .operator(let op, _):
                switch op {
                    case .lparen:
                        return .prefixexp(try await prefixexp())
                    case .lbrace:
                        return try await table()
                    case .sub, .not, .len:
                        try await next()
                        return .unop(op, try await expitem()) // TODO: fix ^ precedence
                    default:
                        throw Error.syntaxError(message: "unexpected symbol", token: current)
                }
            case .name:
                return .prefixexp(try await prefixexp())
            case nil:
                throw Error.syntaxError(message: "expected expression", token: current)
        }
    }

    private static let precedence: [LuaLexer.Operator: Int] = [
        .or: 0,
        .and: 1,
        .lt: 2, .gt: 2, .le: 2, .ge: 2, .eq: 2, .ne: 2,
        .concat: 3,
        .add: 4, .sub: 4,
        .mul: 5, .div: 5, .mod: 5,
        .not: 6, .len: 6,
        .pow: 7
    ]

    private mutating func exp() async throws -> Expression {
        let line = lexer.line
        defer {coder.line = line}
        var ops = [LuaLexer.Operator]()
        var out = [try await expitem()]
        loop: while case let .operator(op, _) = current {
            switch op {
                case .add, .sub, .mul, .div, .mod, .pow, .concat, .eq, .ne, .gt, .lt, .ge, .le, .and, .or: break
                default: break loop
            }
            while let op2 = ops.last, LuaParser.precedence[op2]! > LuaParser.precedence[op]! || (LuaParser.precedence[op2]! == LuaParser.precedence[op]! && !(op == .concat || op == .pow)) {
                let right = out.removeLast()
                let left = out.removeLast()
                if op2 == .pow, case let .unop(op, v) = left {
                    out.append(.unop(op, .binop(op2, v, right)))
                } else {
                    out.append(.binop(op2, left, right))
                }
                ops.removeLast()
            }
            ops.append(op)
            try await next()
            out.append(try await expitem())
        }
        while !ops.isEmpty {
            let right = out.removeLast()
            let left = out.removeLast()
            if ops.last == .pow, case let .unop(op, v) = left {
                out.append(.unop(op, .binop(ops.removeLast(), v, right)))
            } else {
                out.append(.binop(ops.removeLast(), left, right))
            }
        }
        assert(out.count == 1)
        return out[0]
    }

    private mutating func funcbody(addSelf: Bool) async throws -> Int {
        let line = lexer.line
        defer {coder.line = line}
        try await consume(operator: .lparen)
        var args = [String]()
        var vararg = false
        if addSelf {args.append("self")}
        if case let .operator(op, _) = current, op == .rparen {
            try await next()
        } else if case let .constant(k, _) = current, k == .vararg {
            try await next()
            try await consume(operator: .rparen)
            vararg = true
        } else {
            args.append(try await readName())
            while case let .operator(op, _) = current, op == .comma {
                try await next()
                if case let .constant(k, _) = current, k == .vararg {
                    try await next()
                    vararg = true
                    break
                }
                args.append(try await readName())
            }
            try await consume(operator: .rparen)
        }
        coder.line = line
        let idx = coder.function(with: args, vararg: vararg)
        try await block()
        coder.line = lexer.line
        try coder.end()
        try await consume(keyword: .end)
        return idx
    }

    private mutating func table() async throws -> Expression {
        try await consume(operator: .lbrace)
        var fields = [TableEntry]()
        while true {
            switch current {
                case .operator(let op, _):
                    switch op {
                        case .lbracket:
                            try await next()
                            let key = try await exp()
                            try await consume(operator: .rbracket)
                            try await consume(operator: .assign)
                            fields.append(.keyed(key, try await exp()))
                        case .rbrace:
                            try await next()
                            return .table(fields)
                        default:
                            fields.append(.array(try await exp()))
                    }
                case .name(let name, _):
                    let tok = current!
                    try await next()
                    if case let .operator(op, _) = current, op == .assign {
                        try await next()
                        fields.append(.field(name, try await exp()))
                    } else {
                        if let current = current {tokens.append(current)}
                        current = tok
                        fields.append(.array(try await exp()))
                    }
                default:
                    fields.append(.array(try await exp()))
            }
            if case let .operator(op, _) = current, op == .rbrace || op == .comma || op == .semicolon {
                try await next()
                if op == .rbrace {
                    return .table(fields)
                }
            } else {
                throw Error.syntaxError(message: "'}' expected", token: current)
            }
        }
    }

    internal static func parse(from lex: LuaLexer) async throws -> LuaInterpretedFunction {
        var parser = try await LuaParser(from: lex)
        try await parser.block()
        if parser.current != nil {
            throw Error.syntaxError(message: "<eof> expected", token: parser.current)
        }
        try parser.coder.end()
        return parser.coder.encode()
    }
}