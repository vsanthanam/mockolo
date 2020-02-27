
//
//  Copyright (c) 2018. Uber Technologies
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

public enum DeclType {
    case protocolType, classType, extensionType, structType, enumType, typealiasType, varType, funcType, subscriptType,  other
}


final public class Val {
    let path: String
    let parents: [String]
    let start: Int
    let end: Int
    var used = false
    public init(path: String,
                parents: [String],
                start: Int,
                end: Int,
                used: Bool) {
        self.path = path
        self.parents = parents
        self.start = start
        self.end = end
        self.used = used
    }
}


public protocol SourceParsing {
    
    /// Parses processed decls (mock classes) and calls a completion block
    func parseProcessedDecls(_ paths: [String],
                             completion: @escaping ([Entity], [String: [String]]?) -> ())
    
    /// Parses decls (protocol, class) with annotation (/// @mockable) and calls a completion block
    func parseDecls(_ paths: [String]?,
                    isDirs: Bool,
                    exclusionSuffixes: [String]?,
                    annotation: String,
                    completion: @escaping ([Entity], [String: [String]]?) -> ())
}
