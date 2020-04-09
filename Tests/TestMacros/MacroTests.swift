import Foundation

class MacroTests: MockoloTestCase {
   func testMacroInFunc() {
        verify(srcContent: macro,
               dstContent: macroMock,
               parser: .swiftSyntax)
    }

    func testMacroImports() {
         verify(srcContent: macroImports,
                dstContent: macroImportsMock,
                parser: .swiftSyntax)
     }

    func testMacroImportsWithOtherMacro() {
         verify(srcContent: macroImports,
                mockContent: parentMock,
                dstContent: macroImportsMock,
                parser: .swiftSyntax)
     }
}
