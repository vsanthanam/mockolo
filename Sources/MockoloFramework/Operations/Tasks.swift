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


protocol Task {
    var taskHandler: (TaskHandler, [TaskResult]?) -> () { get set }
    init(taskHandler: @escaping (TaskHandler, [TaskResult]?) -> ())

    func perform(on queue: DispatchQueue,
                 with handler: @escaping (TaskResultType) -> ())
}

extension Task {
    
    func perform(on queue: DispatchQueue,
                 with handler: @escaping (TaskResultType) -> ()) {
        queue.async {
            let thandler = TaskHandler(queue: queue, handler: handler)
            self.taskHandler(thandler, nil)
        }
    }
    
    static func group(_ tasks: [Task]) -> Task {
        return Self { (taskHandler, taskResults) in
            let group = DispatchGroup()
            let resultSyncQueue = DispatchQueue(label: "Task.resultSync")
            var taskResults = [TaskResult]()
            for task in tasks {
                group.enter()
                task.perform(on: taskHandler.queue, with: { (result: TaskResultType) in
                    switch result {
                    case .success(let ret):
                        if let ret = ret {
                            resultSyncQueue.sync {
                                taskResults.append(contentsOf: ret)
                            }
                        }
                        break
                    case .failure(let error):
                        break
                    }
                    
                    group.leave()
                })
            }
            
            group.notify(queue: taskHandler.queue) {
                taskHandler.finish(with: taskResults)
            }
        }
    }
    
    static func sequence(_ tasks: [Task]) -> Task {
        var index = 0
        func performNext(using handler: TaskHandler, results: [TaskResult]?) {
            guard index < tasks.count else {
                handler.finish(with: results)
                return
            }
            
            let task = tasks[index]
            index += 1
            task.perform(on: handler.queue) { result in
                switch result {
                case .success(let ret):
                    performNext(using: handler, results: ret)
                default:
                    break
                }
            }
        }
        return Self(taskHandler: performNext)
    }
}


struct ASTTask: Task {
    var taskHandler: (TaskHandler, [TaskResult]?) -> ()
    init(taskHandler: @escaping (TaskHandler, [TaskResult]?) -> ()) {
        self.taskHandler = taskHandler
    }
    
    static func task(filepath: String, exclusionList: [String]?, annotation: String, annotatedOnly: Bool) -> ASTTask {
        return ASTTask { (taskHandler, _) in
            if filepath.shouldParse(with: exclusionList),
                let content = try? String(contentsOfFile: filepath, encoding: .utf8),
                (!annotatedOnly || content.contains(annotation)),
                let top = try? Structure(path: filepath) {
                let entities = top.substructures.filter{$0.isProtocol}.map { (ast: Structure) -> Entity in
                    let annotated = ast.isAnnotated(with: annotation, in: content)
                    return Entity(name: ast.name, filepath: filepath, content: content, ast: ast, isAnnotated: annotated, isProcessed: false)
                }
                taskHandler.finish(with: entities)
            } else {
                taskHandler.fail(with: TaskError.notFound)
            }
        }
    }
}


struct ModelTask: Task {
    var taskHandler: (TaskHandler, [TaskResult]?) -> ()
    
    init(taskHandler: @escaping (TaskHandler, [TaskResult]?) -> ()) {
        self.taskHandler = taskHandler
    }
    
    static func task(entity: Entity, typeKeys: [String: String]?, protocolMap: [String: Entity], inheritanceMap: [String: Entity]) -> ModelTask {
        
        return ModelTask { (taskHandler, _) in
            let ret = generateUniqueModels(key: entity.name, entity: entity, typeKeys: typeKeys, protocolMap: protocolMap, inheritanceMap: inheritanceMap)
            taskHandler.finish(with: [ret])
        }
    }
}

struct EntityTask: Task {
    var taskHandler: (TaskHandler, [TaskResult]?) -> ()
    init(taskHandler: @escaping (TaskHandler, [TaskResult]?) -> ()) {
        self.taskHandler = taskHandler
    }
    
    static func task(ast: Structure, filePath: String, content: String, annotation: String, annotatedOnly: Bool) -> EntityTask {
        return EntityTask { (taskHandler, _) in
            if ast.isProtocol {
                let annotated = ast.isAnnotated(with: annotation, in: content)
                let entity = Entity(name: ast.name, filepath: filePath, content: content, ast: ast, isAnnotated: annotated, isProcessed: false)
                taskHandler.finish(with: [entity])
            } else {
                taskHandler.fail(with: TaskError.notFound)
            }
        }
    }
}


struct WriteTask: Task {
    var taskHandler: (TaskHandler, [TaskResult]?) -> ()
    init(taskHandler: @escaping (TaskHandler, [TaskResult]?) -> ()) {
        self.taskHandler = taskHandler
    }
    
    static func task(candidates: [Output], imports: Set<String>, outputFilePath: String) -> WriteTask {
        return WriteTask { (taskHandler, _) in
            
            let entities = candidates.sorted {$0.offset < $1.offset}.map{$0.content}
            let content = entities.joined(separator: "\n")
            
            let headerStr = String.headerDoc
            let macroStart = "#if MOCK"
            let macroEnd = "#endif"
            let all = [headerStr, macroStart, imports.joined(separator: "\n"), content, macroEnd].joined(separator: "\n\n")
            
            if let ret = try? all.write(toFile: outputFilePath, atomically: true, encoding: .utf8) {
                taskHandler.finish(with: [all])
            } else {
                taskHandler.fail(with: TaskError.notFound)
            }
        }
    }
}

struct ImportTask: Task {
    
    var taskHandler: (TaskHandler, [TaskResult]?) -> ()
    init(taskHandler: @escaping (TaskHandler, [TaskResult]?) -> ()) {
        self.taskHandler = taskHandler
    }
    
    static func task(importLines: [(String, String)]) -> ImportTask {
        return ImportTask { (taskHandler, _) in
            let imports = importLines.map { arg -> [String] in
                let (path, content) = arg
                return findImportLines(content: content)
                }.flatMap {$0}
            taskHandler.finish(with: imports)
        }
    }
}

struct RenderTask: Task {
    
    var taskHandler: (TaskHandler, [TaskResult]?) -> ()
    init(taskHandler: @escaping (TaskHandler, [TaskResult]?) -> ()) {
        self.taskHandler = taskHandler
    }
    
    static func task(entity: ResolvedEntity, typeKeys: [String: String]?) -> RenderTask {
        return RenderTask { (taskHandler, _) in
            let mockModel = entity.model()
            if let mockString = mockModel.render(with: entity.key, typeKeys: typeKeys), !mockString.isEmpty {
                let output = Output(content: mockString, offset: mockModel.offset)
                taskHandler.finish(with: [output])
            } else {
                taskHandler.fail(with: TaskError.notFound)
            }
        }
    }
    
}


struct TaskHandler {
    let queue: DispatchQueue
    let handler: (TaskResultType) -> ()
    
    func finish(with ret: [TaskResult]?) {
        handler(.success(ret))
    }
    func fail(with error: TaskError) {
        handler(.failure(error))
    }
}


