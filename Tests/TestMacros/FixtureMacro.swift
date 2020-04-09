import MockoloFramework

let macroImports = """
import X
import Y

#if DEBUG
import Z
import W
#endif

import V

/// \(String.mockAnnotation)
public protocol SomeProtocol: Parent {
    func run()
}
"""

let parentMock = """
import Foundation

public class ParentMock: Parent {
    public init() {}
}
"""

let macroImportsMock = """
import Foundation
import V
import X
import Y
#if DEBUG
import W
import Z
#endif


public class SomeProtocolMock: SomeProtocol {
    public init() { }

    public var runCallCount = 0
    public var runHandler: (() -> ())?
    public func run()  {
        runCallCount += 1
        if let runHandler = runHandler {
            runHandler()
        }

    }
}

"""


let macro =
"""
/// \(String.mockAnnotation)
protocol PresentableListener: class {
    func run()
    #if DEBUG
    func showDebugMode()
    #endif
}
"""

let macroMock = """

class PresentableListenerMock: PresentableListener {
    
    
    
    init() {  }
    
    var runCallCount = 0
    var runHandler: (() -> ())?
    func run()  {
        runCallCount += 1

        if let runHandler = runHandler {
            runHandler()
        }
        
    }
    #if DEBUG
    var showDebugModeCallCount = 0
    var showDebugModeHandler: (() -> ())?
    func showDebugMode()  {
        showDebugModeCallCount += 1

        if let showDebugModeHandler = showDebugModeHandler {
            showDebugModeHandler()
        }
        
    }
    #endif
}

"""
