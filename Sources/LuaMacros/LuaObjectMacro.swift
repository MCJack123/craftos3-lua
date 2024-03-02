import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin
import SwiftDiagnostics

@main
struct LuaMacros: CompilerPlugin {
    var providingMacros: [Macro.Type] = [LuaObjectMacro.self]
}

public enum LuaMacroError: Error {
    case typeError(node: TypeSyntax, text: String)
    case declarationError
    case testError
    
    var localizedDescription: String {
        switch self {
            case .typeError(_, let text):
                return "Unsupported type \(text)"
            case .declarationError:
                return "Attribute is not supported on this declaration type"
            case .testError:
                return "Test Error"
        }
    }
}

private func convert(type: TypeSyntax, atParameter index: Int, defaultValue: InitializerClauseSyntax?, context: some MacroExpansionContext) throws -> StmtSyntax {
    var type = type
    var optional = false
    if let typ = type.as(OptionalTypeSyntax.self) {
        optional = true
        type = typ.wrappedType
    }
    if let typ = type.as(IdentifierTypeSyntax.self) {
        switch typ.name.text {
            case "LuaValue":
                return "let _\(raw: index) = args[\(raw: index)]"
            case "Bool":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") args.checkBool(at: \(raw: index))\n"
            case "Int":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") args.checkInt(at: \(raw: index))\n"
            case "Double":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") args.checkNumber(at: \(raw: index))\n"
            case "String":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") args.checkString(at: \(raw: index))\n"
            case "LuaTable":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") args.checkTable(at: \(raw: index))\n"
            case "LuaFunction":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") args.checkFunction(at: \(raw: index))\n"
            case "LuaThread":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") args.checkThread(at: \(raw: index))\n"
            default:
                let e = LuaMacroError.typeError(node: type, text: typ.name.text)
                context.addDiagnostics(from: e, node: type)
                throw e
        }
    }
    let e = LuaMacroError.typeError(node: type, text: type.trimmedDescription)
    context.addDiagnostics(from: e, node: type)
    throw e
}

private func convert(typeForReturnValue type: TypeSyntax, context: some MacroExpansionContext) throws -> ExprSyntax {
    if let typ = type.as(TupleTypeSyntax.self) {
        var items = [ArrayElementSyntax]()
        for (i, t) in typ.elements.enumerated() {
            if let typ = t.type.as(OptionalTypeSyntax.self) {
                if let typ = typ.as(IdentifierTypeSyntax.self) {
                    switch typ.name.text.replacingOccurrences(of: ",", with: "") {
                        case "LuaValue":
                            items.append(ArrayElementSyntax(expression: ExprSyntax("res.\(raw: i) ?? .nil, ")))
                        case "Bool":
                            items.append(ArrayElementSyntax(expression: ExprSyntax("res != nil ? .boolean(res.\(raw: i)!) : .nil, ")))
                        case "Int":
                            items.append(ArrayElementSyntax(expression: ExprSyntax("res != nil ? .number(Double(res.\(raw: i)!)) : .nil, ")))
                        case "Double":
                            items.append(ArrayElementSyntax(expression: ExprSyntax("res != nil ? .number(res.\(raw: i)!) : .nil, ")))
                        case "String":
                            items.append(ArrayElementSyntax(expression: ExprSyntax("res != nil ? .string(.string(res.\(raw: i)!)) : .nil, ")))
                        case "LuaTable":
                            items.append(ArrayElementSyntax(expression: ExprSyntax("res != nil ? .table(res.\(raw: i)!) : .nil, ")))
                        case "LuaFunction":
                            items.append(ArrayElementSyntax(expression: ExprSyntax("res != nil ? .function(res.\(raw: i)!) : .nil, ")))
                        case "LuaThread":
                            items.append(ArrayElementSyntax(expression: ExprSyntax("res != nil ? .thread(res.\(raw: i)!) : .nil, ")))
                        default:
                            let e = LuaMacroError.typeError(node: type, text: typ.name.text)
                            context.addDiagnostics(from: e, node: type)
                            throw e
                    }
                } else {
                    let e = LuaMacroError.typeError(node: type, text: t.trimmedDescription)
                    context.addDiagnostics(from: e, node: type)
                    throw e
                }
            } else if let typ = t.type.as(IdentifierTypeSyntax.self) {
                switch typ.name.text.replacingOccurrences(of: ",", with: "") {
                    case "LuaValue":
                        items.append(ArrayElementSyntax(expression: ExprSyntax("res.\(raw: i), ")))
                    case "Bool":
                        items.append(ArrayElementSyntax(expression: ExprSyntax(".boolean(res.\(raw: i)), ")))
                    case "Int":
                        items.append(ArrayElementSyntax(expression: ExprSyntax(".number(Double(res.\(raw: i))), ")))
                    case "Double":
                        items.append(ArrayElementSyntax(expression: ExprSyntax(".number(res.\(raw: i)), ")))
                    case "String":
                        items.append(ArrayElementSyntax(expression: ExprSyntax(".string(.string(res.\(raw: i))), ")))
                    case "LuaTable":
                        items.append(ArrayElementSyntax(expression: ExprSyntax(".table(res.\(raw: i)), ")))
                    case "LuaFunction":
                        items.append(ArrayElementSyntax(expression: ExprSyntax(".function(res.\(raw: i)), ")))
                    case "LuaThread":
                        items.append(ArrayElementSyntax(expression: ExprSyntax(".thread(res.\(raw: i)), ")))
                    default:
                        let e = LuaMacroError.typeError(node: type, text: typ.name.text)
                        context.addDiagnostics(from: e, node: type)
                        throw e
                }
            } else {
                let e = LuaMacroError.typeError(node: type, text: t.trimmedDescription)
                context.addDiagnostics(from: e, node: type)
                throw e
            }
        }
        return "[\(ArrayElementListSyntax(items))]"
    }
    if let typ = type.as(OptionalTypeSyntax.self) {
        if let typ = typ.wrappedType.as(IdentifierTypeSyntax.self) {
            switch typ.name.text {
                case "LuaValue":
                    return "[res ?? .nil]"
                case "Bool":
                    return "[res != nil ? .boolean(res!) : .nil]"
                case "Int":
                    return "[res != nil ? .number(Double(res!)) : .nil]"
                case "Double":
                    return "[res != nil ? .number(res!) : .nil]"
                case "String":
                    return "[res != nil ? .string(.string(res!)) : .nil]"
                case "LuaTable":
                    return "[res != nil ? .table(res!) : .nil]"
                case "LuaFunction":
                    return "[res != nil ? .function(res!) : .nil]"
                case "LuaThread":
                    return "[res != nil ? .thread(res!) : .nil]"
                default:
                    let e = LuaMacroError.typeError(node: type, text: typ.name.text)
                    context.addDiagnostics(from: e, node: type)
                    throw e
            }
        } else {
            let e = LuaMacroError.typeError(node: type, text: type.trimmedDescription)
            context.addDiagnostics(from: e, node: type)
            throw e
        }
    }
    if let typ = type.as(IdentifierTypeSyntax.self) {
        switch typ.name.text {
            case "LuaValue":
                return "[res]"
            case "Bool":
                return "[.boolean(res)]"
            case "Int":
                return "[.number(Double(res))]"
            case "Double":
                return "[.number(res)]"
            case "String":
                return "[.string(.string(res))]"
            case "LuaTable":
                return "[.table(res)]"
            case "LuaFunction":
                return "[.function(res)]"
            case "LuaThread":
                return "[.thread(res)]"
            default:
                let e = LuaMacroError.typeError(node: type, text: typ.name.text)
                context.addDiagnostics(from: e, node: type)
                throw e
        }
    }
    if let typ = type.as(ArrayTypeSyntax.self), let typ2 = typ.element.as(IdentifierTypeSyntax.self), typ2.name.text == "LuaValue" {
        return "res"
    }
    let e = LuaMacroError.typeError(node: type, text: type.trimmedDescription)
    context.addDiagnostics(from: e, node: type)
    throw e
}

public struct LuaObjectMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let cname: String
        if let c = declaration.as(ActorDeclSyntax.self) {
            cname = c.name.text
        } else if let c = declaration.as(ClassDeclSyntax.self) {
            cname = c.name.text
        } else if let c = declaration.as(EnumDeclSyntax.self) {
            cname = c.name.text
        } else if let c = declaration.as(StructDeclSyntax.self) {
            cname = c.name.text
        } else {
            throw LuaMacroError.declarationError
        }
        let funcs = declaration.memberBlock.members
            .compactMap {$0.decl.as(FunctionDeclSyntax.self)}
            .filter {$0.modifiers.contains {$0.name.text == "public"}}
        let methods: [DeclSyntax] = try funcs
            .filter {!$0.modifiers.contains {$0.name.text == "static"}}
            .map {(fn) -> DeclSyntax in
                var params = [FunctionParameterSyntax](fn.signature.parameterClause.parameters)
                var argcheck = [StmtSyntax]()
                var call = "_self.\(fn.name.text)("
                if params.first?.type.as(IdentifierTypeSyntax.self)?.name.text == "Lua" {
                    call += (params.first!.firstName.text == "_" ? "" : params.first!.firstName.text + ": ") + "state, "
                    params.removeFirst()
                }
                if params.first?.type.as(IdentifierTypeSyntax.self)?.name.text == "LuaArgs" {
                    call += (params.first!.firstName.text == "_" ? "" : params.first!.firstName.text + ": ") + "args, "
                } else {
                    for (i, param) in params.enumerated() {
                        argcheck.append(try convert(type: param.type, atParameter: i + 2, defaultValue: param.defaultValue, context: context))
                        call += (param.firstName.text == "_" ? "" : param.firstName.text + ": ") + "_\(i + 2), "
                    }
                }
                if call.hasSuffix(", ") {call = String(call[call.startIndex..<call.index(call.endIndex, offsetBy: -2)])}
                if fn.signature.effectSpecifiers?.asyncSpecifier != nil {
                    call = "await " + call
                }
                if fn.signature.effectSpecifiers?.throwsSpecifier != nil {
                    call = "try " + call
                }
                call += ")"
                if let ret = fn.signature.returnClause {
                    return """
                    let _\(raw: fn.name.text) = LuaSwiftFunction {state, args in
                        let _self = try args.checkUserdata(at: 1, as: \(raw: cname).self)
                        \(CodeBlockItemListSyntax(argcheck.map {CodeBlockItemSyntax(item: .stmt($0))}))
                        let res = \(raw: call)
                        return \(try convert(typeForReturnValue: ret.type, context: context))
                    }
                    """
                }
                return """
                let _\(raw: fn.name.text) = LuaSwiftFunction {state, args in
                    let _self = try args.checkUserdata(at: 1, as: \(raw: cname).self)
                    \(CodeBlockItemListSyntax(argcheck.map {CodeBlockItemSyntax(item: .stmt($0))}))
                    \(raw: call)
                    return []
                }
                """
            }
        return methods
    }
}
