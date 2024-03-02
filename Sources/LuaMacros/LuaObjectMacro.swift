import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin

@main
struct LuaMacros: CompilerPlugin {
    var providingMacros: [Macro.Type] = [LuaObjectMacro.self]
}

public enum LuaMacroError: Error {
    case typeError(node: TypeSyntax, text: String)
}

private func convert(type: TypeSyntax, at index: Int, defaultValue: InitializerClauseSyntax?) throws -> StmtSyntax {
    var type = type
    var optional = false
    if let typ = type.as(OptionalTypeSyntax.self) {
        optional = true
        type = typ.wrappedType
    }
    if let typ = type.as(IdentifierTypeSyntax.self) {
        switch typ.name {
            case "Int":
                return "let _\(raw: index) = args.checkInt(at: \(raw: index))\n"
            case "Double":
                return "let _\(raw: index) = args.checkDouble(at: \(raw: index))\n"
            case "Bool":
                return "let _\(raw: index) = args.checkBool(at: \(raw: index))\n"
            case "String":
                return "let _\(raw: index) = args.checkString(at: \(raw: index))\n"
            default: throw LuaMacroError.typeError(node: type, text: String(cString: type.syntaxTextBytes))
        }
    }
    throw LuaMacroError.typeError(node: type, text: String(cString: type.syntaxTextBytes))
}

public struct LuaObjectMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let funcs = declaration.memberBlock.members
            .compactMap {$0.decl.as(FunctionDeclSyntax.self)}
            .filter {$0.modifiers.contains {$0.name == "public"}}
        let methods = funcs
            .filter {!$0.modifiers.contains {$0.name == "static"}}
            .map {fn in
                let params = fn.signature.parameterClause.parameters
                if params.first?.type.as(IdentifierTypeSyntax.self)?.name == "Lua" {
                    
                }
            }
        return []
    }
}
