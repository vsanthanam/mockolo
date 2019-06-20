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

func executeTasks(dirs: [String]?,
                          files: [String]?,
                          exclusionSuffixes: [String]? = nil,
                          annotatedOnly: Bool,
                          annotation: String,
                          outputFilePath: String,
                          semaphore: DispatchSemaphore?,
                          queue: DispatchQueue?,
                          process: @escaping (String) -> ()) {
    
    var paths = [""]
    if let dirs = dirs {
        paths = scanPaths(dirs) ?? [""]
    } else if let files = files {
        paths = files
    }
    
    log("Parsing", paths.count, "dirs / files...")
    let t0 = CFAbsoluteTimeGetCurrent()
    let astTasks = paths.map { (filePath: String) -> ASTTask in
        return ASTTask.task(filepath: filePath,
                            exclusionList: exclusionSuffixes,
                            annotation: annotation,
                            annotatedOnly: annotatedOnly)
    }
    
    let astGroup = ASTTask.group(astTasks)
    let astSeq = ASTTask.sequence([astGroup])
    if let queue = queue {
        astSeq.perform(on: queue) { (entityResult: TaskResultType) in
//            if let astList = (try? astResult.get()) as? [AST] {
            
            
//                let entityTasks = astList.map { (ast: AST) -> [EntityTask] in
//                    let top = ast.ast
//                    let subTasks = top.substructures.map { (sub: Structure) -> EntityTask in
//                        return EntityTask.task(ast: sub, filePath: ast.filePath, content: ast.content, annotation: annotation, annotatedOnly: annotatedOnly)
//                    }
//                    return subTasks
//                    }.flatMap {$0}
//                let entityGroup = EntityTask.group(entityTasks)
//                let entitySeq = EntityTask.sequence([entityGroup])
                //let mapSQ = DispatchQueue(label: "Task.mapSync")
//                entitySeq.perform(on: queue, with: { (entityResult: TaskResultType) in
                    if let entityList = (try? entityResult.get()) as? [Entity] {
                        let t2 = CFAbsoluteTimeGetCurrent()
                        log("Took", t2-t0, level: .verbose)
                        log("Resolving models for", entityList.count, "entities...")
                        
                        let annotatedEntities = entityList.filter {$0.isAnnotated}
                        var entityDict = [String: Entity]()
                        var typeKeys = [String: String]()  // add parentmocks too
                        
                        //mapSQ.sync {
                            for ent in entityList {
                                entityDict[ent.name] = ent
                            }
                            annotatedEntities.forEach { ent in
                                let t = ent.name
                                typeKeys[t] = "\(t)Mock()"
                            }
                        //}
                        let inh = [String: Entity]()
                        
                        let modelTasks = annotatedEntities.map { ent -> ModelTask in
                            return ModelTask.task(entity: ent, typeKeys: typeKeys, protocolMap: entityDict, inheritanceMap: inh)
                        }
                        
                        let modelGroup = ModelTask.group(modelTasks)
                        let modelSeq = ModelTask.sequence([modelGroup])
                        
                        modelSeq.perform(on: queue, with: { (resolvedResult: TaskResultType) in
                            if let resList = (try? resolvedResult.get()) as? [Resolved] {
                                let t3 = CFAbsoluteTimeGetCurrent()
                                log("Took", t3-t2, level: .verbose)
                                log("Render models ...")
                                
                                let renderTasks = resList.map { resEnt -> RenderTask in
                                    return RenderTask.task(entity: resEnt.entity, typeKeys: typeKeys)
                                }
                                
                                let renderGroup = RenderTask.group(renderTasks)
                                let renderSeq = RenderTask.sequence([renderGroup])
                                
                                renderSeq.perform(on: queue, with: { (renderResult: TaskResultType) in
                                    if let renderList = (try? renderResult.get()) as? [Output] {
                                        let t4 = CFAbsoluteTimeGetCurrent()
                                        log("Took", t4-t3, level: .verbose)
                                        log("Import lines...")
                                        
                                        
                                        let importTasks = resList.map { resEnt -> ImportTask in
                                            return ImportTask.task(importLines: resEnt.imports)
                                        }
                                        let importGroup = ImportTask.group(importTasks)
                                        let importSeq = ImportTask.sequence([importGroup])
                                        importSeq.perform(on: queue, with: { (importResult: TaskResultType) in
                                            if let importList = (try? importResult.get()) as? [String] {
                                                let t5 = CFAbsoluteTimeGetCurrent()
                                                log("Took", t5-t4, level: .verbose)
                                                log("Write results to \(outputFilePath)...")
                                                
                                                let importsSet = Set(importList)
                                                let writeTask = WriteTask.task(candidates: renderList, imports: importsSet, outputFilePath: outputFilePath)
                                                let writeGroup = WriteTask.group([writeTask])
                                                let writeSeq = WriteTask.sequence([writeGroup])
                                                writeSeq.perform(on: queue, with: { (done: TaskResultType) in
                                                    if let results = (try? done.get()) as? [String] {
                                                        let t6 = CFAbsoluteTimeGetCurrent()
                                                        log("Done. Total took", t6-t0, level: .verbose)
                                                        let loc = results.first?.components(separatedBy: "\n").count ?? 0
                                                        
                                                        log("#Protocols = \(entityDict.count), #Annotated protocols = \(annotatedEntities.count), #Parent mock classes = 0, #Final mock classes = \(renderList.count), File LoC = \(loc)", level: .verbose)
                                                        process("DONE")
                                                    }
                                                })
                                            }
                                        })
                                    }
                                })
                            }
                        })
                    }
//                })
//            }
        }
    }
}



protocol TaskResult {}

typealias TaskResultType = Result<[TaskResult]?, TaskError>
extension String: TaskResult {}
extension Entity: TaskResult {}
struct Output: TaskResult {
    let content: String
    let offset: Int64
}

extension ResolvedEntityContainer: TaskResult {}

//struct ASTResult: TaskResult {
//    let ast: Structure
//    let filePath: String
//    let content: String
//}


enum TaskError: Error {
    case notFound
}

public enum Result<Value, ErrorType: Error> {
    /// Indicates success with value in the associated object.
    case success(Value)
    
    /// Indicates failure with error inside the associated object.
    case failure(ErrorType)

    public func get() throws -> Value {
        fatalError()
    }
}

