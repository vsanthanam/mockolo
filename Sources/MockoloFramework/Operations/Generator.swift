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

enum InputError: Error {
    case annotationError
    case sourceFilesError
}

public enum ParserType {
    case swiftSyntax
    case sourceKit
}

/// Performs end to end mock generation flow
public func generate(sourceDirs: [String]?,
                     sourceFiles: [String]?,
                     parser: SourceParsing,
                     exclusionSuffixes: [String],
                     mockFilePaths: [String]?,
                     annotation: String,
                     header: String?,
                     macro: String?,
                     to outputFilePath: String,
                     loggingLevel: Int,
                     concurrencyLimit: Int?,
                     onCompletion: @escaping (String) -> ()) throws {
    
    guard sourceDirs != nil || sourceFiles != nil else {
        log("Source files or directories do not exist", level: .error)
        throw InputError.sourceFilesError
    }
    
    minLogLevel = loggingLevel
    var candidates = [(String, Int64)]()
    var parentMocks = [String: Entity]()
    var annotatedProtocolMap = [String: Entity]()
    var protocolMap = [String: Entity]()
    var pathToContentMap = [(String, Data, Int64)]()
    var pathToImportsMap = [String: [String]]()
    var relevantPaths = [String]()
    var resolvedEntities = [ResolvedEntity]()
    
    let maxConcurrentThreads = concurrencyLimit ?? 0
    let sema = maxConcurrentThreads <= 1 ? nil: DispatchSemaphore(value: maxConcurrentThreads)
    let mockgenQueue = maxConcurrentThreads == 1 ? nil: DispatchQueue(label: "mockgen-q", qos: DispatchQoS.userInteractive, attributes: DispatchQueue.Attributes.concurrent)
    
    signpost_begin(name: "Process input")
    let t0 = CFAbsoluteTimeGetCurrent()
    log("Process input mock files...", level: .info)
    if let mockFilePaths = mockFilePaths, !mockFilePaths.isEmpty {
        parser.parseProcessedDecls(mockFilePaths,
                                   semaphore: sema,
                                   queue: mockgenQueue) { (elements, imports) in
                                    elements.forEach { element in
                                        parentMocks[element.entityNode.name] = element
                                    }
                                    
                                    if let imports = imports {
                                        for (path, modules) in imports {
                                            if pathToImportsMap[path] == nil {
                                                pathToImportsMap[path] = []
                                            }
                                            pathToImportsMap[path]?.append(contentsOf: modules)
                                        }
                                    }
        }
    }
    signpost_end(name: "Process input")
    let t1 = CFAbsoluteTimeGetCurrent()
    log("Took", t1-t0, level: .verbose)
    
    signpost_begin(name: "Generate protocol map")
    log("11111111 Process source files and generate an annotated/protocol map...", level: .info)
    
    let paths = sourceDirs ?? sourceFiles
    let isDirs = sourceDirs != nil
    parser.parseDecls(paths,
                      isDirs: isDirs,
                      exclusionSuffixes: exclusionSuffixes,
                      annotation: annotation,
                      semaphore: sema,
                      queue: mockgenQueue) { (elements, imports) in
                        elements.forEach { element in
                            protocolMap[element.entityNode.name] = element
                            if element.isAnnotated {
                                annotatedProtocolMap[element.entityNode.name] = element
                            }
                        }
                        if let imports = imports {
                            for (path, modules) in imports {
                                if pathToImportsMap[path] == nil {
                                    pathToImportsMap[path] = []
                                }
                                pathToImportsMap[path]?.append(contentsOf: modules)
                            }
                        }
    }
    signpost_end(name: "Generate protocol map")
    let t2 = CFAbsoluteTimeGetCurrent()
    log("Took", t2-t1, level: .verbose)
    
    signpost_begin(name: "Generate models")
    let typeKeyList = [parentMocks.compactMap {$0.key.components(separatedBy: "Mock").first}, annotatedProtocolMap.map {$0.key}].flatMap{$0}
    var typeKeys = [String: String]()
    typeKeyList.forEach { (t: String) in
        typeKeys[t] = "\(t)Mock()"
    }
    
    log("Resolve inheritance and generate unique entity models...", level: .info)
    
    generateUniqueModels(protocolMap: protocolMap,
                         annotatedProtocolMap: annotatedProtocolMap,
                         inheritanceMap: parentMocks,
                         typeKeys: typeKeys,
                         semaphore: sema,
                         queue: mockgenQueue,
                         completion: { container in
                            pathToContentMap.append(contentsOf: container.imports)
                            relevantPaths.append(contentsOf: container.paths)
                            resolvedEntities.append(container.entity)
    })
    signpost_end(name: "Generate models")
    let t3 = CFAbsoluteTimeGetCurrent()
    log("Took", t3-t2, level: .verbose)
    
    signpost_begin(name: "Render models")
    log("Render models with templates...", level: .info)
    renderTemplates(entities: resolvedEntities,
                    typeKeys: typeKeys,
                    semaphore: sema,
                    queue: mockgenQueue,
                    completion: { (mockString: String, offset: Int64) in
                        candidates.append((mockString, offset))
    })
    signpost_end(name: "Render models")
    let t4 = CFAbsoluteTimeGetCurrent()
    log("Took", t4-t3, level: .verbose)
    
    signpost_begin(name: "Write results")
    log("Write the mock results and import lines to", outputFilePath, level: .info)
    let result = write(candidates: candidates,
                       pathToImportsMap: pathToImportsMap,
                       relevantPaths: relevantPaths,
                       pathToContentMap: pathToContentMap,
                       header: header,
                       macro: macro,
                       to: outputFilePath)
    signpost_end(name: "Write results")
    let t5 = CFAbsoluteTimeGetCurrent()
    log("Took", t5-t4, level: .verbose)
    
    let count = result.components(separatedBy: "\n").count
    log("TOTAL", t5-t0, level: .verbose)
    log("#Protocols = \(protocolMap.count), #Annotated protocols = \(annotatedProtocolMap.count), #Parent mock classes = \(parentMocks.count), #Final mock classes = \(candidates.count), File LoC = \(count)", level: .verbose)
    
    onCompletion(result)
}


//  public struct Key: Hashable {
//      let path: String
//      let name: String
//  }

public typealias Key = String
public struct Val {
    let acl: String
    let annotated: Bool
    let parents: [String]
}
  
public let adata = "@CreateMock".data(using: String.Encoding.utf8)

var pmaps = [Key: Val]()
var kmaps = [Key: Val]()
var rmap = [Key: [String]]()
let pr1 = ParserViaSourceKit()
let pr2 = ParserViaSwiftSyntax()
let root = "/Users/ellie/uber/mirror/ios/" //"/Users/ellieshin/Developer/uber/ios"
let depfile =  "helix-deps.txt"
let xlist = ["TestCase", "Scene", "Screen", "Images", "Strings", "Objc", "Resources", "Mocks", "Mock", "Tests", "Test", "Drawables", "AssetCatalog", "Fixtures", "Fixture", "Model", "Models", "Service", "Services", "Generated"]
let dirs = [root + "/libraries/foundation", root + "/libraries/common", root + "/libraries/feature", root + "/apps/iphone-helix/src/Uber"]

var fcount = 1
public func omg() {
    let sema = DispatchSemaphore(value: 12)
    let q = DispatchQueue(label: "qq", qos: DispatchQoS.userInteractive, attributes: DispatchQueue.Attributes.concurrent)

    print("1")
    let t0 = CFAbsoluteTimeGetCurrent()
    pr2.asdf(dirs, exclusionSuffixes: xlist, sema: sema, q: q) { (p, k) in
        pmaps.merge(p, uniquingKeysWith: { (l, h) -> Val in l })
        kmaps.merge(k, uniquingKeysWith: { (l, h) -> Val in l })
    }
    let t1 = CFAbsoluteTimeGetCurrent()
    
    print("2", t1-t0)

    for (k, v) in kmaps {
        kol(key: k, val: v)
    }
    let t2 = CFAbsoluteTimeGetCurrent()
    print("3", t2-t1)

    let rsorted = rmap.sorted { (lhs: (key: Key, value: [String]), rhs: (key: Key, value: [String])) -> Bool in
        return lhs.value.count < rhs.value.count
    }

    let t3 = CFAbsoluteTimeGetCurrent()
    print("4", t3-t2)
    let single = rsorted.filter{$0.value.count <= 1}
    let totalAn = rsorted.filter{pmaps[$0.key]?.annotated ?? false}
    let singleAn = single.filter{pmaps[$0.key]?.annotated ?? false}
    let totalPublic = rsorted.filter{pmaps[$0.key]?.acl ?? "" == "public"}
    let singlePublic = single.filter{pmaps[$0.key]?.acl ?? "" == "public"}
    print(rsorted.count, single.count)
    print(totalAn.count, singleAn.count)
    print(totalPublic.count, singlePublic.count)
    
    
    var liststr = ""
    for s in single {
        liststr.append("\n\(s.key) : \(s.value.first ?? "")")
    }
    
    try? liststr.write(toFile: root + "/pkmaps\(fcount)", atomically: true, encoding: .utf8)
    fcount += 1
    
//    10254 9302
//    8875 8238
//    4161 3463
//
//    10254 9302
//    8874 8239
//    4159 3462
    
//    10238 9401
//    8883 8289
//    4078 3467

    
    
// TODO: #file #LOC

    var singlemap = [Key: String]()
    for ent in single {
        if let f = ent.value.first {
            singlemap[ent.key] = f
        }
    }
    
    // for (p, [k]) in single
    //  if curnode is p, remove the node
    //  if curnode is protocol and inherits p, remove decl p
    //  if curnode is class (k) and conforms to p, remove decl p, ----------  match p's acl to k's acl
    //  if curnode is a member (var, func, init param), replace type p with k
    pr2.rewrite(dirs, pass: 1, with: singlemap, exclusionSuffixes: xlist) { (path, content) in
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    let t4 = CFAbsoluteTimeGetCurrent()
    print("5", t4-t3)

    pr2.rewrite(dirs, pass: 2, with: singlemap, exclusionSuffixes: xlist) { (path, content) in
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    
    let t5 = CFAbsoluteTimeGetCurrent()
    print("6", t5-t4)


    // TODO:
    // profile startup time before and after
    // add delta to ERD

    // replace pMock with kMock in tests
    // push diff -- 1 giant diff
}


func kol(key: Key, val: Val) {
//    if val.parents.isEmpty {
//        return
//    }

    for i in val.parents {
//        if let ent = kmaps[i] {
//            kol(key: i, val: ent)
//        }
        if let ent = pmaps[i] {
            if rmap[i] == nil {
                rmap[i] = []
            }
            rmap[i]?.append(key)
        }
    }
}
