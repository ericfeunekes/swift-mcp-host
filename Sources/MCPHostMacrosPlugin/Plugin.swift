import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MCPHostMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        MCPToolMacro.self,
        MCPSchemaMacro.self,
        MCPEnumMacro.self,
    ]
}
