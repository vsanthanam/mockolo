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

public typealias Loc = (name: String, docLoc: (Int, Int))
public struct Entry {
    var path: String
    var module: String
    var parents: [String]
    var annotated: Bool = false
    var docLoc: (Int, Int) = (0, 0)
}

public func cleanup(sourceDirs: [String]?,
                    exclusionSuffixes: [String]? = nil,
                    annotation: String,
                    outputFilePath: String? = nil,
                    concurrencyLimit: Int? = nil) {
    
    let dirs = sourceDirs ?? []
    let p = ParserViaSwiftSyntax()

    var protocolMap = [String : Entry]()
    var annotatedProtocolMap = [String : Entry]()
    var usedTypeToModuleMap = [String: [String]]()
    
    log("Scan all mockables...")
    let t0 = CFAbsoluteTimeGetCurrent()
    p.scanMockables(dirs: dirs, exclusionSuffixes: exclusionSuffixes, annotation: annotation) { (filePath, initialUsedTypes, argProtocolMap) in
        let module = filePath.module
        for (k, v) in argProtocolMap {
            protocolMap[k] = v
            if v.annotated {
                annotatedProtocolMap[k] = v
            }
        }
        
        for u in initialUsedTypes {
            usedTypeToModuleMap[u] = []
        }
    }
    
    let t1 = CFAbsoluteTimeGetCurrent()
    log("----", t1-t0)

    
    log("Gather used types...")
    for k in usedTypeToModuleMap.keys {
        if let m = protocolMap[k]?.path.module {
            usedTypeToModuleMap[k] = [m]
        }
    }
    
    log("Resolve used types...")
    var resolvedUsedTypeMap = usedTypeToModuleMap
    for (curType, curVal) in usedTypeToModuleMap {
        resolveUsedTypes(curType, protocolMap: protocolMap, usedTypeMap: usedTypeToModuleMap, result: &resolvedUsedTypeMap, level: 0)
    }
    
    let t2 = CFAbsoluteTimeGetCurrent()
    log("----", t2-t1)

    log("Scan used types...") // in tests or manual mocks
    p.scanUsedTypes(dirs: dirs, exclusionSuffixes: nil) { (filePath, argUsedTypes) in
        let pathstr = filePath.components(separatedBy: "Tests").first ?? ""
        let module = pathstr.module
        let usedSet = Set(argUsedTypes)
        for usedType in usedSet {
            if resolvedUsedTypeMap[usedType] == nil {
                resolvedUsedTypeMap[usedType] = []
            }
            
            if let list = resolvedUsedTypeMap[usedType], !list.contains(module) {
                resolvedUsedTypeMap[usedType]?.append(module)
            }
        }
    }
    let t3 = CFAbsoluteTimeGetCurrent()
    log("----", t3-t2)

    
    log("Filter out unused types...")
    var unusedTypeMap = [String: Entry]()
    for (k, v) in annotatedProtocolMap {
        if resolvedUsedTypeMap[k] == nil {
            unusedTypeMap[k] = v
        }
    }
    
    log("Save unused types...")
    let pathToUnsedTypes = saveUnusedTypes(unusedTypeMap, resolvedUsedTypeMap, outputFilePath)
    
    log("Remove unnecessary annotations from files...")
    removeAnnotationsFromUnusedTypes(dirs, exclusionSuffixes, annotation, pathToUnsedTypes)
    let t4 = CFAbsoluteTimeGetCurrent()
    
    log("#Protocols", protocolMap.count, "#Annotated", annotatedProtocolMap.count, "Used Types", resolvedUsedTypeMap.count, "Unused Types", unusedTypeMap.count, "#Files w/ unused types", pathToUnsedTypes.count)
    log("Total (s)", t4-t0)
}


private func resolveUsedTypes(_ curType: String,
                              protocolMap: [String: Entry],
                              usedTypeMap: [String: [String]],
                              result: inout [String: [String]],
                              level: Int) {
    
    if let entry = protocolMap[curType] {
        for p in entry.parents {
            if let val = result[p], val.contains(p) {
                // already added to used list, so do nothing
            } else {
                if let m = protocolMap[p]?.path.module {
                    if result[p] == nil {
                        result[p] = []
                    }
                    if let ms = result[p], !ms.contains(m) {
                        result[p]?.append(m)
                    }
                    resolveUsedTypes(p, protocolMap: protocolMap, usedTypeMap: usedTypeMap, result: &result, level: level+1)
                }
            }
        }
    }
}

public func saveUnusedTypes(_ unusedTypeMap: [String: Entry],
                            _ resolvedUsedTypeMap: [String: [String]],
                            _ outputFilePath: String?) -> [String: [Entry]] {
    
    var pathToUnusedTypes = [String: [Entry]]()
    
    let unusedListStr = unusedTypeMap.map { (k, v) -> String in
        if pathToUnusedTypes[v.path] == nil {
            pathToUnusedTypes[v.path] = []
        }
        pathToUnusedTypes[v.path]?.append(v)
        return k + ": " + v.path.module + " -- " + v.path
    }.joined(separator: "\n")
    
    
    let retNoModules = resolvedUsedTypeMap.filter {$0.value.isEmpty}
    let retModules = resolvedUsedTypeMap.filter {!$0.value.isEmpty}
    let usedListStr = retModules.map { (k, v) -> String in
        return k + ": " + v.joined(separator: ", ")
    }
    let usedListStrNoMdoules = retNoModules.map { (k, v) -> String in
        return k + ": " + v.joined(separator: ", ")
    }
    
    let ulist = [usedListStr, usedListStrNoMdoules].flatMap{$0}.joined(separator: "\n")

    
    log("Found", unusedTypeMap.count, " unused protocols in ", pathToUnusedTypes.count, "files.", "-- Used types: ", resolvedUsedTypeMap.count)
    if let outputFilePath = outputFilePath {
        try? unusedListStr.write(toFile: outputFilePath, atomically: true, encoding: .utf8)
        log("Saving to", outputFilePath)
        try? ulist.write(toFile: outputFilePath + "-used", atomically: true, encoding: .utf8)
        log("Saving to", outputFilePath + "-used")
    }
    return pathToUnusedTypes
}

public func removeAnnotationsFromUnusedTypes(_ dirs: [String],
                                             _ exclusionSuffixes: [String]?,
                                             _ annotation: String,
                                             _ pathToUnsedTypes: [String: [Entry]]) {
    
    utilScan(dirs: dirs) { (filePath, lock) in
        replace(filePath, pathToUnsedTypes[filePath], exclusionSuffixes, annotation, lock) { data in
            let url = URL(fileURLWithPath: filePath)
            do {
                try data.write(to: url, options: Data.WritingOptions.atomicWrite)
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
}

public func replace(_ path: String,
                     _ entries: [Entry]?,
                     _ exclusionSuffixes: [String]?,
                     _ annotation: String,
                     _ lock: NSLock?,
                     _ completion: @escaping (Data) -> ()) {
    let original = "/// \(annotation)"
    let newline = "\n"
    let space = String(repeating: " ", count: original.count)
    
    guard !path.contains("___"), path.shouldParse(with: exclusionSuffixes) else { return }
    
    guard let originalData = original.data(using: .utf8),
        let newlineData = newline.data(using: .utf8),
        let spaceData = space.data(using: .utf8),
        let entries = entries else {return}
    
    guard var content = FileManager.default.contents(atPath: path) else {
        fatalError("Retrieving contents of \(path) failed")
    }
    
    var ranges = [Range<Data.Index>]()
    for entry in entries {
        let start = entry.docLoc.0
        let end = entry.docLoc.1
        
        if let annotationRange = content.range(of: originalData, options: [], in: start..<end) {
            let anStart = annotationRange.startIndex
            let anEnd = annotationRange.endIndex
            if let newlingRange = content.range(of: newlineData, options: [], in: anEnd..<end) {
                let lineStart = newlingRange.startIndex
                
                if lineStart == anEnd {
                    ranges.append(annotationRange)
                } else {
                    ranges.append(anStart..<lineStart)
                }
            }
        }
    }
    
    for r in ranges {
        let len = r.endIndex-r.startIndex
        if len == originalData.count {
            content.replaceSubrange(r, with: spaceData)
        } else {
            if let extraSpaces = String(repeating: " ", count: len).data(using: .utf8) {
                content.replaceSubrange(r, with: extraSpaces)
            }
        }
    }
    
    lock?.lock()
    completion(content)
    lock?.unlock()
}

