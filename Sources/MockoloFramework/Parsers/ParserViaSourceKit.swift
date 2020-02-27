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
import SourceKittenFramework

public class ParserViaSourceKit: SourceParsing {
    
    public init() {}
    
    public func parseProcessedDecls(_ paths: [String],
                                    completion: @escaping ([Entity], [String: [String]]?) -> ()) {
        utilScan(files: paths) { (filePath, lock) in
            self.generateProcessedASTs(filePath, lock: lock, completion: completion)
        }
    }
    
    public func parseDecls(_ paths: [String]?,
                           isDirs: Bool,
                           exclusionSuffixes: [String]? = nil,
                           annotation: String,
                           completion: @escaping ([Entity], [String: [String]]?) -> ()) {
        guard !annotation.isEmpty else { return }
        guard let paths = paths else { return }
        if isDirs {
            generateASTs(dirs: paths, exclusionSuffixes: exclusionSuffixes, annotation: annotation, completion: completion)
        } else {
            generateASTs(files: paths, exclusionSuffixes: exclusionSuffixes, annotation: annotation, completion: completion)
        }
    }
    
    private func generateASTs(dirs: [String],
                              exclusionSuffixes: [String]? = nil,
                              annotation: String,
                              completion: @escaping ([Entity], [String: [String]]?) -> ()) {
        
        guard let annotationData = annotation.data(using: .utf8) else {
            fatalError("Annotation is invalid: \(annotation)")
        }
        
        utilScan(dirs: dirs) { (path, lock) in
            self.generateASTs(path,
                              exclusionSuffixes: exclusionSuffixes,
                              annotationData: annotationData,
                              lock: lock,
                              completion: completion)
        }
    }
    
    private func generateASTs(files: [String],
                              exclusionSuffixes: [String]? = nil,
                              annotation: String,
                              completion: @escaping ([Entity], [String: [String]]?) -> ()) {
        guard let annotationData = annotation.data(using: .utf8) else {
            fatalError("Annotation is invalid: \(annotation)")
        }
        utilScan(files: files) { (path, lock) in
            self.generateASTs(path,
                              exclusionSuffixes: exclusionSuffixes,
                              annotationData: annotationData,
                              lock: lock,
                              completion: completion)
            
        }
    }
    
    private func generateASTs(_ path: String,
                              exclusionSuffixes: [String]? = nil,
                              annotationData: Data,
                              lock: NSLock?,
                              completion: @escaping ([Entity], [String: [String]]?) -> ()) {
        
        guard path.shouldParse(with: exclusionSuffixes) else { return }
        guard let content = FileManager.default.contents(atPath: path) else {
            fatalError("Retrieving contents of \(path) failed")
        }
        
        do {
            var results = [Entity]()
            let topstructure = try Structure(path: path)
            for current in topstructure.substructures {
                let metadata = current.annotationMetadata(with: annotationData, in: content)
                if let node = Entity.node(with: current, path: path, data: content, isPrivate: current.isPrivate, isFinal: current.isFinal, metadata: metadata, processed: false) {
                    results.append(node)
                }
            }
            
            lock?.lock()
            completion(results, nil)
            lock?.unlock()
            
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    private func generateProcessedASTs(_ path: String,
                                       lock: NSLock?,
                                       completion: @escaping ([Entity], [String: [String]]) -> ()) {
        
        guard let content = FileManager.default.contents(atPath: path) else {
            fatalError("Retrieving contents of \(path) failed")
        }
        
        do {
            let topstructure = try Structure(path: path)
            let subs = topstructure.substructures
            let results = subs.compactMap { current -> Entity? in
                return Entity.node(with: current, path: path, data: content, isPrivate: current.isPrivate, isFinal: current.isFinal, metadata: nil, processed: true)
            }
            
            let imports = findImportLines(data: content, offset: subs.first?.offset)
            lock?.lock()
            completion(results, [path: imports])
            lock?.unlock()
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    
    func scanDecls(dirs: [String],
                   exclusionSuffixes: [String]? = nil,
                   completion: @escaping ([String: Val]) -> ()) {
        utilScan(dirs: dirs) { (path: String, lock: NSLock?) in
            guard path.shouldParse(with: exclusionSuffixes) else { return }
            do {
                var results = [String: Val]()
                let topstructure = try Structure(path: path)
                for current in topstructure.substructures {
                    if (current.isProtocol  || current.isClass), !current.name.hasPrefix("_"), !current.name.hasPrefix("UB"), !current.name.hasSuffix("Objc"), !current.name.contains("__VARIABLE_"), !current.inheritedTypes.contains("NSObject") {
                        if let attrs = current.attributeValues {
                            let hasobjc = attrs.filter{$0.contains("objc")}
                            if !hasobjc.isEmpty {
                                continue
                            }
                        }
                        
                        results[current.name] = Val(path: path, parents: current.inheritedTypes, start: current.startOffset, end: current.endOffset, used: false)
                    }
                }
                
                lock?.lock()
                completion(results)
                lock?.unlock()
                
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
    
    
    
    func scanUsedDecls(dirs: [String],
                       exclusionSuffixes: [String]? = nil,
                       completion: @escaping ([String]) -> ()) {
        
        utilScan(dirs: dirs) { (path, lock) in
            guard path.shouldParse(with: exclusionSuffixes) else { return }
            guard let content = FileManager.default.contents(atPath: path) else {
                fatalError("Retrieving contents of \(path) failed")
            }
            do {
                var results = [String]()
                let topstructure = try Structure(path: path)
                for current in topstructure.substructures {
                    
                    if current.isProtocol || current.isClass {
                        results.append(contentsOf: current.inheritedTypes.map{$0.typeComponents}.flatMap{$0})
                    } else if current.isExtension {
                        results.append(current.name)
                        results.append(contentsOf: current.inheritedTypes.map{$0.typeComponents}.flatMap{$0})
                    }
                    
                    // This handles members of class/extensions as well as unparsed items such as global decls, typealias rhs value, Type.self
                    let ret = self.parseContent(content: content, start: Int(current.nameOffset + current.nameLength), end: Int(current.offset+current.length))
                    results.append(contentsOf: ret)
                    
                    #if USESOURCEKIT
                    if current.kind == "source.lang.swift.decl.var.global", !(current.typeName == .unknownVal || current.typeName.isEmpty || current.typeName == "Void") {
                        results.append(contentsOf: current.typeName.typeComponents)
                    }
                    if current.kind == "source.lang.swift.expr.call" {
                        results.append(contentsOf: current.name.typeComponents)
                    }
                    if current.kind == "source.lang.swift.decl.function.free", !(current.typeName == .unknownVal || current.typeName.isEmpty || current.typeName == "Void") {
                        results.append(contentsOf: current.typeName.typeComponents)
                    }
                    gatherUsedDecls(current, results: &results)
                    #endif
                }
                
                lock?.lock()
                completion(results)
                lock?.unlock()
                
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
    
    
    func removeUnusedDecls(declMap: [String: Val],
                           queue: DispatchQueue?,
                           semaphore: DispatchSemaphore?,
                           completion: @escaping (Data, URL) -> ()) {
        if let queue = queue {
            let lock = NSLock()
            for (decl, val) in declMap {
                _ = semaphore?.wait(timeout: DispatchTime.distantFuture)
                queue.async {
                    self.removeUnusedDecls(val.path,
                                           decl: decl,
                                           start: val.start,
                                           end: val.end,
                                           lock: lock,
                                           completion: completion)
                    semaphore?.signal()
                }
            }
            
            // Wait for queue to drain
            queue.sync(flags: .barrier) {}
        }
    }
    
    let space = UInt8(32)
    let newline = UInt8(10)
    func removeUnusedDecls(_ path: String,
                           decl: String,
                           start: Int,
                           end: Int,
                           lock: NSLock?,
                           completion: @escaping (Data, URL) -> ()) {
        guard var content = FileManager.default.contents(atPath: path) else {
            fatalError("Retrieving contents of \(path) failed")
        }
        if content.isEmpty { return }
        let spaces = Data(repeating: space, count: end-start)
        let range = start..<end
        content.replaceSubrange(range, with: spaces)
        
        let url = URL(fileURLWithPath: path)
        
        lock?.lock()
        completion(content, url)
        lock?.unlock()
    }
    
    func checkUnused(_ dirs: [String],
                     unusedList: [String],
                     exclusionSuffixes: [String]?,
                     queue: DispatchQueue?,
                     semaphore: DispatchSemaphore?,
                     completion: @escaping ([String]) -> ()) {
        
        if let queue = queue {
            let lock = NSLock()
            scanPaths(dirs) { filepath in
                // test file path
                _ = semaphore?.wait(timeout: DispatchTime.distantFuture)
                queue.async {
                    self.checkUnused(filepath,
                                     unusedList: unusedList,
                                     exclusionSuffixes: exclusionSuffixes,
                                     lock: lock,
                                     completion: completion)
                    semaphore?.signal()
                }
            }
            // Wait for queue to drain
            queue.sync(flags: .barrier) {}
        }
    }
    
    func checkUnused(_ filepath: String,
                     unusedList: [String],
                     exclusionSuffixes: [String]?,
                     lock: NSLock?,
                     completion: @escaping ([String]) -> ()) {
        guard filepath.shouldParse(with: exclusionSuffixes) else { return }
        do {
            let topstructure = try Structure(path: filepath)
            var toRemove = [String]()
            for current in topstructure.substructures {
                guard current.isProtocol || current.isClass else { continue }
                if unusedList.contains(current.name) {
                    toRemove.append(current.name)
                }
            }
            lock?.lock()
            completion(toRemove)
            lock?.unlock()
        } catch {
            log(error.localizedDescription)
        }
    }
    
    func updateTests(dirs: [String],
                     unusedMap: [String: Val],
                     queue: DispatchQueue?,
                     semaphore: DispatchSemaphore?,
                     completion: @escaping (Data, URL, Int, Bool) -> ()) {
        if let queue = queue {
            let lock = NSLock()
            scanPaths(dirs) { filepath in
                // test file path
                _ = semaphore?.wait(timeout: DispatchTime.distantFuture)
                queue.async {
                    self.updateTest(filepath,
                                    unusedMap: unusedMap,
                                    lock: lock,
                                    completion: completion)
                    semaphore?.signal()
                }
            }
            // Wait for queue to drain
            queue.sync(flags: .barrier) {}
        }
    }
    
    func updateTest(_ path: String,
                    unusedMap: [String: Val],
                    lock: NSLock?,
                    completion: @escaping (Data, URL, Int, Bool) -> ()) {
        
        guard path.hasSuffix("Tests.swift") || path.hasSuffix("Test.swift") else { return }
        
        guard var content = FileManager.default.contents(atPath: path) else {
            fatalError("Retrieving contents of \(path) failed")
        }
        
        do {
            let topstructure = try Structure(path: path)
            var toDelete = [String: (Int, Int)]()
            var deleteCount = 0
            var declsInFile = 0
            for current in topstructure.substructures {
                guard current.isClass else { continue }
                var testname = current.name
                if testname.hasSuffix("SnapshotTests") {
                    testname = String(testname.dropLast("SnapshotTests".count))
                    declsInFile += 1
                } else if testname.hasSuffix("SnapshotTest") {
                    testname = String(testname.dropLast("SnapshotTest".count))
                    declsInFile += 1
                } else if testname.hasSuffix("Tests") {
                    testname = String(testname.dropLast("Tests".count))
                    declsInFile += 1
                } else if testname.hasSuffix("Test") {
                    testname = String(testname.dropLast("Test".count))
                    declsInFile += 1
                }
                
                if let _ = unusedMap[testname] {
                    // 1. if it's the test name
                    //if v.path.module == path.module { // TODO: need this?
                    toDelete[testname] = (current.startOffset, current.endOffset)
                    deleteCount += 1
                    //                    print("DELETE", current.name, testname)
                    //}
                } else {
                    //                    print("IN body: ", current.name, testname)
                    
                    // 2. if it's within the test body as var decls, func bodies, exprs, return val, etc.
                    // Then remove the whole function or class using it
                    // let x = UnusedClass()  <--- removing this requires removing occurrences of x (or expr itself) or replacing it with a subsitution everywhere.
                    // let x: UnusedClass     <--- removing this requires above and also assignment to x
                    updateBody(current, unusedMap: unusedMap, content: &content)
                }
            }
            
            let shouldDelete = deleteCount > 0 && declsInFile == deleteCount
            
            if !shouldDelete {
                for (k, v) in toDelete {
                    replace(&content, start: v.0, end: v.1, with: space)
                }
            }
            
            let url = URL(fileURLWithPath: path)
            lock?.lock()
            completion(content, url, deleteCount, shouldDelete)
            lock?.unlock()
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    private func replace(_ content: inout Data, start: Int, end: Int, with another: UInt8) {
        if start > 0, end > start {
            let anotherData = Data(repeating: another, count: end-start)
            let range = start..<end
            content.replaceSubrange(range, with: anotherData)
        }
    }
    
    private func updateBody(_ current: Structure,
                            unusedMap: [String: Val],
                            content: inout Data) {
        for sub in current.substructures {
            let types = [sub.name.typeComponents, sub.typeName.typeComponents].flatMap{$0}
            for t in types {
                var tname = t
                if t.hasSuffix("Mock") {
                    tname = String(t.dropLast("Mock".count))
                }
                if unusedMap[tname] != nil {
                    //                    print("FOUND", t, current.name)
                    replace(&content, start: sub.startOffset, end: sub.endOffset, with: space)
                }
            }
            updateBody(sub, unusedMap: unusedMap, content: &content)
        }
    }
    
    private func parseContent(content: Data, start: Int, end: Int) -> [String] {
        guard start > 0, end > start else { return [] }
        let range = start..<end
        let subdata = content.subdata(in: range)
        if let str = String(data: subdata, encoding: .utf8) {
            var buffer = [String]()
            let comps = str.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter{!$0.isEmpty}
            for c in comps {
                buffer.append(contentsOf: c.typeComponents)
            }
            return buffer
        }
        return []
    }
    
    
    private func gatherUsedDecls(_ current: Structure, results: inout [String]) {
        for sub in current.substructures {
            if sub.kind == SwiftDeclarationKind.genericTypeParam.rawValue {
                results.append(contentsOf: sub.name.typeComponents)
            }
            
            if sub.kind == "source.lang.swift.decl.var.parameter" {
                results.append(contentsOf: sub.typeName.typeComponents)
            }
            
            if sub.kind == "source.lang.swift.expr.call" {
                results.append(contentsOf: sub.name.typeComponents)
            }
            
            if sub.isVariable || sub.kind == "source.lang.swift.decl.var.local", sub.typeName != .unknownVal {
                results.append(contentsOf: sub.typeName.typeComponents)
            }
            
            if sub.isMethod || sub.kind == "source.lang.swift.decl.function.method.class", !(sub.typeName == .unknownVal || sub.typeName.isEmpty || sub.typeName == "Void") {
                results.append(contentsOf: sub.typeName.typeComponents)
            }
            
            gatherUsedDecls(sub, results: &results)
        }
    }
    
    
    public func stats(dirs: [String],
                      exclusionSuffixes: [String]? = nil,
                      completion: @escaping (Int, Int) -> ()) {
        utilScan(dirs: dirs) { (path: String, lock: NSLock?) in
            guard path.shouldParse(with: exclusionSuffixes) else {return}
            do {
                var pcount = 0
                var kcount = 0
                let topstructure = try Structure(path: path)
                for current in topstructure.substructures {
                    if current.isProtocol {
                        pcount += 1
                    }
                    if current.isClass {
                        kcount += 1
                    }
                }
                
                completion(pcount, kcount)
            } catch {
                fatalError()
            }
        }
    }
    
}
