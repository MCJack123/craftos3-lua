import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin
import SwiftDiagnostics

public struct LuaObjectMacro: MemberMacro, ExtensionMacro {
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

        let objectExtension: DeclSyntax =
            """
            extension \(type.trimmed): LuaObject {
                public var userdata: LuaUserdata {return LuaUserdata(for: self, with: \(type.trimmed).metatable)}
            }
            """

        guard let extensionDecl = objectExtension.as(ExtensionDeclSyntax.self) else {
            return []
        }

        return [extensionDecl]
    }

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
        var metatable = ""
        let funcs = declaration.memberBlock.members
            .compactMap {$0.decl.as(FunctionDeclSyntax.self)}
            .filter {$0.modifiers.contains {$0.name.text == "public"}}
        var retval: [DeclSyntax] = try funcs
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
                    call += (params.first!.firstName.text == "_" ? "" : params.first!.firstName.text + ": ") + "LuaArgs([LuaValue](args.args[1...]), state: state), "
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
                metatable += """
                    case \"\(fn.name.text)\": return [.function(.swift(\(cname)._\(fn.name.text)))]
                    """
                if let ret = fn.signature.returnClause {
                    return """
                    static let _\(raw: fn.name.text) = LuaSwiftFunction {state, args in
                        let _self = try args.checkUserdata(at: 1, as: \(raw: cname).self)
                        \(CodeBlockItemListSyntax(argcheck.map {CodeBlockItemSyntax(item: .stmt($0))}))
                        let res = \(raw: call)
                        return \(try convert(typeForReturnValue: ret.type, context: context))
                    }
                    """
                }
                return """
                static let _\(raw: fn.name.text) = LuaSwiftFunction {state, args in
                    let _self = try args.checkUserdata(at: 1, as: \(raw: cname).self)
                    \(CodeBlockItemListSyntax(argcheck.map {CodeBlockItemSyntax(item: .stmt($0))}))
                    \(raw: call)
                    return []
                }
                """
            }
        retval.append(contentsOf: try funcs
            .filter {$0.modifiers.contains {$0.name.text == "static"}}
            .map {(fn) -> DeclSyntax in
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
                metatable += """
                    case \"\(fn.name.text)\": return [.function(.swift(\(cname)._\(fn.name.text)))]
                    """
                if let ret = fn.signature.returnClause {
                    return """
                    static let _\(raw: fn.name.text) = LuaSwiftFunction {state, args in
                        \(CodeBlockItemListSyntax(argcheck.map {CodeBlockItemSyntax(item: .stmt($0))}))
                        let res = \(raw: call)
                        return \(try convert(typeForReturnValue: ret.type, context: context))
                    }
                    """
                }
                return """
                static let _\(raw: fn.name.text) = LuaSwiftFunction {state, args in
                    \(CodeBlockItemListSyntax(argcheck.map {CodeBlockItemSyntax(item: .stmt($0))}))
                    \(raw: call)
                    return []
                }
                """
            })
        var index = "return [.nil]"
        var metamethods = ""
        if let ss = declaration.memberBlock.members
            .compactMap({$0.decl.as(SubscriptDeclSyntax.self)})
            .filter({
                $0.modifiers.contains {$0.name.text == "public"} &&
                $0.parameterClause.parameters.count == 1 &&
                $0.parameterClause.parameters.first!.type.as(IdentifierTypeSyntax.self)?.name.text == "LuaValue" &&
                $0.returnClause.type.as(IdentifierTypeSyntax.self)?.name.text == "LuaValue"})
            .first {
            index = "return [_self[args[2]]]"
            if ss.accessorBlock?.accessors.as(AccessorDeclListSyntax.self)?
                .contains(where: {$0.accessorSpecifier.text == "set"}) ?? false {
                retval.append("""
                    static let __newindex = LuaSwiftFunction {state, args in
                        let _self = try args.checkUserdata(at: 1, as: \(raw: cname).self)
                        _self[args[2]] = args[3]
                        return []
                    }
                    """)
                metamethods += ".string(.string(\"__newindex\")): .function(.swift(\(cname).__newindex)),\n"
            }
        }
            
        retval.append(contentsOf: [
            """
            static let metatable = LuaTable(from: [
                .string(.string("__index")): .function(.swift(LuaSwiftFunction {state, args in
                    let _self = try args.checkUserdata(at: 1, as: \(raw: cname).self)
                    if case let .string(idx) = args[2] {
                        switch idx.string {
                            \(raw: metatable)
                            default: \(raw: index)
                        }
                    }
                    \(raw: index)
                })),
                \(raw: metamethods)
                .string(.string("__name")): .string(.string("\(raw: cname)"))
            ])
            """
        ])
        return retval
    }
}
