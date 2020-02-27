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
import SwiftSyntax

public class ParserViaSwiftSyntax: SourceParsing {
    
    public init() {}
    
    public func parseProcessedDecls(_ paths: [String],
                                    completion: @escaping ([Entity], [String: [String]]?) -> ()) {
        utilScan(files: paths) { (path, lock) in
            self.generateASTs(path, annotation: "", lock: lock, completion: completion)
        }
    }
    
    public func parseDecls(_ paths: [String]?,
                           isDirs: Bool,
                           exclusionSuffixes: [String]? = nil,
                           annotation: String,
                           completion: @escaping ([Entity], [String: [String]]?) -> ()) {
        
        guard let paths = paths else { return }

        if isDirs {
            utilScan(dirs: paths) { (path, lock) in
                self.generateASTs(path,
                             exclusionSuffixes: exclusionSuffixes,
                             annotation: annotation,
                             lock: lock,
                             completion: completion)
            }
        } else {
            utilScan(files: paths) { (path, lock) in
                self.generateASTs(path,
                                  exclusionSuffixes: exclusionSuffixes,
                                  annotation: annotation,
                                  lock: lock,
                                  completion: completion)
            }
        }
    }
    
    private func generateASTs(_ path: String,
                              exclusionSuffixes: [String]? = nil,
                              annotation: String,
                              lock: NSLock?,
                              completion: @escaping ([Entity], [String: [String]]?) -> ()) {
        
        guard path.shouldParse(with: exclusionSuffixes) else { return }
        do {
            var results = [Entity]()
            let node = try SyntaxParser.parse(path)
            var treeVisitor = EntityVisitor(path, annotation: annotation)
            node.walk(&treeVisitor)
            let ret = treeVisitor.entities
            results.append(contentsOf: ret)
            let imports = treeVisitor.imports

            lock?.lock()
            defer {lock?.unlock()}
            completion(results, [path: imports])
            treeVisitor.reset()
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    public func scanMockables(dirs: [String],
                              exclusionSuffixes: [String]?,
                              annotation: String,
                              completion: @escaping (String, [String], [String: Entry]) -> ()) {
        utilScan(dirs: dirs) { (path, lock) in
            guard !path.contains("___"), path.shouldParse(with: exclusionSuffixes) else { return }
            
            do {
                let node = try SyntaxParser.parse(path)
                var visitor = CleanerVisitor(annotation: annotation, path: path, root: node)
                node.walk(&visitor)
                lock?.lock()
                defer {lock?.unlock()}
                completion(path, visitor.usedTypes, visitor.protocolMap)
                visitor.reset()
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
    
    func scanUsedTypes(dirs: [String],
                       exclusionSuffixes: [String]?,
                       completion: @escaping (String, [String]) -> ()) {
        
        utilScan(dirs: dirs) { (path, lock) in
            guard !path.contains("___"),
                path.hasSuffix(".swift"),
                (path.contains("Test") || path.contains("Mocks.swift") || path.contains("Mock.swift")) else { return }
            
            do {
                let node = try SyntaxParser.parse(path)
                var visitor = CleanerVisitor(annotation: "", path: path, root: node)
                node.walk(&visitor)
                lock?.lock()
                defer {lock?.unlock()}
                
                completion(path, visitor.usedTypes.filter{!$0.isEmpty})
                visitor.reset()
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
    
    
    public func stats(dirs: [String],
                      exclusionSuffixes: [String]? = nil,
                      numThreads: Int? = nil,
                      completion: @escaping (Int, Int) -> ()) {
        utilScan(dirs: dirs) { (path: String, lock: NSLock?) in
            guard path.shouldParse(with: exclusionSuffixes) else {return}
            do {
                let node = try SyntaxParser.parse(path)
                let rewriter = CleanerWriter()
                _ = rewriter.visit(node)
                
                lock?.lock()
                defer {lock?.unlock()}
                completion(rewriter.k, rewriter.p)
            } catch {
                fatalError()
            }
        }
    }
    
    
    func scanDecls(dirs: [String],
                   exclusionSuffixes: [String]? = nil,
                   completion: @escaping (String, [String: [String]]) -> ()) {
        utilScan(dirs: dirs) { (path: String, lock: NSLock?) in
            guard path.shouldParse(with: exclusionSuffixes) else { return }
            do {
                var k = 0
                let node = try SyntaxParser.parse(path)
                var visitor = DeclVisitor(path)
                node.walk(&visitor)
                
                lock?.lock()
                defer {lock?.unlock()}
                completion(path, visitor.declMap)
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }

    func scanRefs(dirs: [String],
                   exclusionSuffixes: [String]? = nil,
                   completion: @escaping (String, [String], [String]) -> ()) {
        utilScan(dirs: dirs) { (path: String, lock: NSLock?) in
            guard path.shouldParse(with: exclusionSuffixes) else { return }
            do {
//                var results = [String: Val]()
//                var k = 0
                let node = try SyntaxParser.parse(path)
                var visitor = RefVisitor(path)
                node.walk(&visitor)

                lock?.lock()
                completion(path, visitor.refs, visitor.imports)
                lock?.unlock()
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }

    func removeUnusedImports(dirs: [String],
                             exclusionSuffixes: [String]? = nil,
                             unusedImports: [String: [String]],
                             completion: @escaping (String, String) -> ()) {

        utilScan(dirs: dirs) { (path, lock) in
            guard path.shouldParse(with: exclusionSuffixes) else { return }
                        do {
            //                var results = [String: Val]()
            //                var k = 0
                            let node = try SyntaxParser.parse(path)
                            var remover = ImportRemover(path, unusedModules: unusedImports[path])
                            let ret = remover.visit(node)

                            lock?.lock()
                            completion(path, ret.description)
                            lock?.unlock()
                        } catch {
                            fatalError(error.localizedDescription)
                        }

        }

    }
}
