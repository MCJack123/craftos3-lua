import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin
import SwiftDiagnostics

@main
struct LuaMacros: CompilerPlugin {
    var providingMacros: [Macro.Type] = [LuaObjectMacro.self, LuaLibraryMacro.self]
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

internal func convert(type: TypeSyntax, atParameter index: Int, defaultValue: InitializerClauseSyntax?, context: some MacroExpansionContext) throws -> StmtSyntax {
    var type = type
    var optional = false
    if let typ = type.as(OptionalTypeSyntax.self) {
        optional = true
        type = typ.wrappedType
    }
    if let typ = type.as(IdentifierTypeSyntax.self) {
        switch typ.name.text {
            case "LuaValue":
                return "let _\(raw: index) = args[\(raw: index)]\(raw: optional ? ".optional" : "")"
            case "Bool":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") await args.checkBool(at: \(raw: index))\n"
            case "Int":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") await args.checkInt(at: \(raw: index))\n"
            case "Double":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") await args.checkNumber(at: \(raw: index))\n"
            case "String":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") await args.checkString(at: \(raw: index))\n"
            case "LuaTable":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") await args.checkTable(at: \(raw: index))\n"
            case "LuaFunction":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") await args.checkFunction(at: \(raw: index))\n"
            case "LuaThread":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") await args.checkThread(at: \(raw: index))\n"
            case "LuaUserdata":
                return "let _\(raw: index) = \(raw: optional ? "try?" : "try") await args.checkUserdata(at: \(raw: index))\n"
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

internal func convert(typeForReturnValue type: TypeSyntax, context: some MacroExpansionContext) throws -> ExprSyntax {
    if let typ = type.as(TupleTypeSyntax.self) {
        var items = [ArrayElementSyntax]()
        for (i, t) in typ.elements.enumerated() {
            if let typ = t.type.as(OptionalTypeSyntax.self) {
                if let typ = typ.wrappedType.as(IdentifierTypeSyntax.self) {
                    switch typ.name.text {
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
                        case "LuaUserdata":
                            items.append(ArrayElementSyntax(expression: ExprSyntax("res != nil ? .userdata(res.\(raw: i)!) : .nil, ")))
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
                switch typ.name.text {
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
                    case "LuaUserdata":
                        items.append(ArrayElementSyntax(expression: ExprSyntax(".userdata(res.\(raw: i)), ")))
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
                case "LuaUserdata":
                    return "[res != nil ? .userdata(res!) : .nil]"
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
            case "LuaUserdata":
                return "[.userdata(res)]"
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
