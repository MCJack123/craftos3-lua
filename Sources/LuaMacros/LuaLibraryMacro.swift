import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin
import SwiftDiagnostics

public struct LuaLibraryMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        if protocols.isEmpty {
            return []
        }

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
        var retval = DictionaryElementListSyntax(try funcs
            .filter {!$0.modifiers.contains {$0.name.text == "static"}}
            .map {(fn) -> DictionaryElementSyntax in
                var params = [FunctionParameterSyntax](fn.signature.parameterClause.parameters)
                var argcheck = [StmtSyntax]()
                var call = "self.\(fn.name.text)("
                if params.first?.type.as(IdentifierTypeSyntax.self)?.name.text == "Lua" {
                    call += (params.first!.firstName.text == "_" ? "" : params.first!.firstName.text + ": ") + "state, "
                    params.removeFirst()
                }
                if params.first?.type.as(IdentifierTypeSyntax.self)?.name.text == "LuaArgs" {
                    call += (params.first!.firstName.text == "_" ? "" : params.first!.firstName.text + ": ") + "args, "
                } else {
                    for (i, param) in params.enumerated() {
                        argcheck.append(try convert(type: param.type, atParameter: i + 1, defaultValue: param.defaultValue, context: context))
                        call += (param.firstName.text == "_" ? "" : param.firstName.text + ": ") + "_\(i + 1), "
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
                    return DictionaryElementSyntax(
                        key: ExprSyntax(".string(.string(\"\(raw: fn.name.text)\"))"),
                        value: ExprSyntax("""
                            .function(.swift(LuaSwiftFunction {state, args in
                                \(CodeBlockItemListSyntax(argcheck.map {CodeBlockItemSyntax(item: .stmt($0))}))
                                let res = \(raw: call)
                                return \(try convert(typeForReturnValue: ret.type, context: context))
                            }))
                            """),
                        trailingComma: TokenSyntax(.comma, presence: .present),
                        trailingTrivia: Trivia(stringLiteral: "\n"))
                }
                return DictionaryElementSyntax(
                    key: ExprSyntax(".string(.string(\"\(raw: fn.name.text)\"))"),
                    value: ExprSyntax("""
                        .function(.swift(LuaSwiftFunction {state, args in
                            \(CodeBlockItemListSyntax(argcheck.map {CodeBlockItemSyntax(item: .stmt($0))}))
                            \(raw: call)
                            return []
                        }))
                        """),
                    trailingComma: TokenSyntax(.comma, presence: .present),
                    trailingTrivia: Trivia(stringLiteral: "\n"))
            })
        retval.append(contentsOf: try funcs
            .filter {$0.modifiers.contains {$0.name.text == "static"}}
            .map {(fn) -> DictionaryElementSyntax in
                var params = [FunctionParameterSyntax](fn.signature.parameterClause.parameters)
                var argcheck = [StmtSyntax]()
                var call = "\(cname).\(fn.name.text)("
                if params.first?.type.as(IdentifierTypeSyntax.self)?.name.text == "Lua" {
                    call += (params.first!.firstName.text == "_" ? "" : params.first!.firstName.text + ": ") + "state, "
                    params.removeFirst()
                }
                if params.first?.type.as(IdentifierTypeSyntax.self)?.name.text == "LuaArgs" {
                    call += (params.first!.firstName.text == "_" ? "" : params.first!.firstName.text + ": ") + "args, "
                } else {
                    for (i, param) in params.enumerated() {
                        argcheck.append(try convert(type: param.type, atParameter: i + 1, defaultValue: param.defaultValue, context: context))
                        call += (param.firstName.text == "_" ? "" : param.firstName.text + ": ") + "_\(i + 1), "
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
                    return DictionaryElementSyntax(
                        key: ExprSyntax(".string(.string(\"\(raw: fn.name.text)\"))"),
                        value: ExprSyntax("""
                            .function(.swift(LuaSwiftFunction {state, args in
                                \(CodeBlockItemListSyntax(argcheck.map {CodeBlockItemSyntax(item: .stmt($0))}))
                                let res = \(raw: call)
                                return \(try convert(typeForReturnValue: ret.type, context: context))
                            }))
                            """),
                        trailingComma: TokenSyntax(.comma, presence: .present),
                        trailingTrivia: Trivia(stringLiteral: "\n"))
                }
                return DictionaryElementSyntax(
                    key: ExprSyntax(".string(.string(\"\(raw: fn.name.text)\"))"),
                    value: ExprSyntax("""
                         .function(.swift(LuaSwiftFunction {state, args in
                            \(CodeBlockItemListSyntax(argcheck.map {CodeBlockItemSyntax(item: .stmt($0))}))
                            \(raw: call)
                            return []
                        }))
                        """),
                    trailingComma: TokenSyntax(.comma, presence: .present),
                    trailingTrivia: Trivia(stringLiteral: "\n"))
            })
        retval.append(contentsOf: declaration.memberBlock.members
            .compactMap {$0.decl.as(VariableDeclSyntax.self)}
            .filter {
                $0.modifiers.contains {$0.name.text == "public"} &&
                $0.modifiers.contains {$0.name.text == "static"} &&
                $0.bindingSpecifier.text == "let"
            }
            .flatMap {$0.bindings}
            .filter {$0.initializer != nil && $0.pattern.is(IdentifierPatternSyntax.self)}
            .map {(v: PatternBindingSyntax) -> DictionaryElementSyntax in
                return DictionaryElementSyntax(
                    key: ExprSyntax(".string(.string(\"\(raw: v.pattern.as(IdentifierPatternSyntax.self)!.identifier.text)\"))"),
                    value: ExprSyntax(".value(\(v.initializer!.value))"),
                    trailingComma: TokenSyntax(.comma, presence: .present),
                    trailingTrivia: Trivia(stringLiteral: "\n"))
            })

        let objectExtension: DeclSyntax =
            """
            extension \(type.trimmed): LuaLibrary {
                public var name: String {return \(node.arguments!.as(LabeledExprListSyntax.self)!.first!.expression)}
                public var table: LuaTable {
                    return LuaTable(from: [
                        \(retval)
                    ])
                }
            }
            """

        guard let extensionDecl = objectExtension.as(ExtensionDeclSyntax.self) else {
            return []
        }

        return [extensionDecl]
    }
}
