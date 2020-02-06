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

final class SomeWriter: SyntaxRewriter {
    let tmap: [Key: String]
    let pass: Int
    init(map: [Key: String], pass: Int) {
        self.tmap = map
        self.pass = pass
    }
    
    override func visit(_ token: TokenSyntax) -> Syntax {
        guard self.pass == 2  else { return token }
        
        let k = token.description.trimmingCharacters(in: .whitespaces)
        if let x = tmap[k] {
            let ret = SyntaxFactory.makeTypeIdentifier(x)
            return ret
        }
        return token
    }

   
    override func visit(_ node: TypeInheritanceClauseSyntax) -> Syntax {

        guard self.pass == 1  else { return node }
        
        let comps = node.inheritedTypeCollection.description.components(separatedBy: CharacterSet(charactersIn: ":, "))

        var filtered = [String]()
        for c in comps {
            if !c.isEmpty, tmap[c] == nil {
                filtered.append(c)
            }
        }
        
        if filtered.count == comps.count {
            return node
        }
        
        if filtered.isEmpty {
            let ret = SyntaxFactory.makeTypeIdentifier(" ")
            return ret
        }
 
        var str = filtered.joined(separator: ", ")
        str = ": \(str) "
        let arg = SyntaxFactory.makeTypeIdentifier(str)
        return arg
    }

    
    
    override func visit(_ node: ExtensionDeclSyntax) -> DeclSyntax {
        guard self.pass == 1  else { return node }

        let k = node.description.trimmingCharacters(in: .whitespaces)
        
        if let x = tmap[k] {
            let ret = SyntaxFactory.makeBlankExtensionDecl()
            return ret
        }
        
        return node
    }

//    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
//        if pass != 2 {return node}
//
//        let k = node.description.trimmingCharacters(in: .whitespaces)
//        if let x = map[k] {
//            let ret = SyntaxFactory.makeBlankProtocolDecl()
//            return ret
//        }
//
//        return node
//    }
    
    override func visit(_ node: ProtocolDeclSyntax) -> DeclSyntax {
        guard self.pass == 1  else { return node }

        let k = node.description.trimmingCharacters(in: .whitespaces)

        if let x = tmap[k] {
            let ret = SyntaxFactory.makeBlankProtocolDecl()
            return ret
        }
        
        return node
    }
}

public class ParserViaSwiftSyntax: SourceParsing {
    
    public func rewrite(_ paths: [String],
                        pass: Int,
                        with map: [Key: String],
                        exclusionSuffixes: [String]? = nil,
                        completion: @escaping (String, String) -> ())  {
        var rw = SomeWriter(map: map, pass: pass)
        
        scanPaths(paths) { filePath in
            if pass == 1 {
            self.pass1(filePath,
                    rewriter: &rw,
                    exclusionSuffixes: exclusionSuffixes,
                    completion: completion)
            }
            
            if pass == 2 {
                self.pass2(filePath,
                        rewriter: &rw,
                        exclusionSuffixes: exclusionSuffixes,
                        completion: completion)

            }
        }
    }
    
    func pass2(_ path: String,
            rewriter: inout SomeWriter,
            exclusionSuffixes: [String]? = nil,
            completion: @escaping (String, String) -> ()) {
        
        guard path.shouldParse(with: exclusionSuffixes) else { return }
        
        do {
            let node = try SyntaxParser.parse(path)
            let ret = rewriter.visit(node)

            var retcontent = ""
            ret.write(to: &retcontent)
             
            completion(path, retcontent)
            
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    func pass1(_ path: String,
            rewriter: inout SomeWriter,
            exclusionSuffixes: [String]? = nil,
            completion: @escaping (String, String) -> ()) {
        
        guard path.shouldParse(with: exclusionSuffixes) else { return }
        
        do {
            let node = try SyntaxParser.parse(path)
            let ret = rewriter.visit(node)

            var retcontent = ""
            ret.write(to: &retcontent)
             
            completion(path, retcontent)
            
        } catch {
            fatalError(error.localizedDescription)
        }
    }
       
    public func asdf(_ paths: [String],
                     exclusionSuffixes: [String]? = nil,
                     sema: DispatchSemaphore? = nil,
                     q: DispatchQueue? = nil,
                     completion: @escaping ([Key: Val], [Key: Val]) -> ()) {
        
        var treeVisitor = SomeVisitor()
        scanPaths(paths) { filePath in
            self.ff(filePath,
                    treeVisitor: &treeVisitor,
                    exclusionSuffixes: exclusionSuffixes,
                    completion: completion)
        }
    }
    
    func ff(_ path: String,
            treeVisitor: inout SomeVisitor,
            exclusionSuffixes: [String]? = nil,
            completion: @escaping ([Key: Val], [Key: Val]) -> ()) {
        
        guard path.shouldParse(with: exclusionSuffixes) else { return }

        guard let content = FileManager.default.contents(atPath: path) else {
            fatalError("Retrieving contents of \(path) failed")
        }
        
        do {
            let node = try SyntaxParser.parse(path)
            node.walk(&treeVisitor)
            
            let l = treeVisitor.ps
            let r = treeVisitor.ks

            completion(l, r)
            treeVisitor.reset()

        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    //////////////////////////////
    
    
    
    public init() {}
    
    public func parseProcessedDecls(_ paths: [String],
                                    semaphore: DispatchSemaphore?,
                                    queue: DispatchQueue?,
                                    completion: @escaping ([Entity], [String: [String]]?) -> ()) {
        var treeVisitor = EntityVisitor()
        for filePath in paths {
            generateASTs(filePath, annotation: "", treeVisitor: &treeVisitor, completion: completion)
        }
    }
    
    public func parseDecls(_ paths: [String]?,
                           isDirs: Bool,
                           exclusionSuffixes: [String]? = nil,
                           annotation: String,
                           semaphore: DispatchSemaphore?,
                           queue: DispatchQueue?,
                           completion: @escaping ([Entity], [String: [String]]?) -> ()) {
        
        guard let paths = paths else { return }
        
        var treeVisitor = EntityVisitor(annotation: annotation)
        
        if isDirs {
            scanPaths(paths) { filePath in
                generateASTs(filePath,
                             exclusionSuffixes: exclusionSuffixes,
                             annotation: annotation,
                             treeVisitor: &treeVisitor,
                             completion: completion)
            }
        } else {
            for filePath in paths {
                generateASTs(filePath, exclusionSuffixes: exclusionSuffixes, annotation: annotation, treeVisitor: &treeVisitor, completion: completion)
            }
            
        }
    }
    
    private func generateASTs(_ path: String,
                              exclusionSuffixes: [String]? = nil,
                              annotation: String,
                              treeVisitor: inout EntityVisitor,
                              completion: @escaping ([Entity], [String: [String]]?) -> ()) {
        
        guard path.shouldParse(with: exclusionSuffixes) else { return }
        do {
            log("-- Generating ASTs ", level: .info)
               
            var results = [Entity]()
            let node = try SyntaxParser.parse(path)
            node.walk(&treeVisitor)
            let ret = treeVisitor.entities
            for ent in ret {
                ent.filepath = path
            }
            results.append(contentsOf: ret)
            let imports = treeVisitor.imports
            treeVisitor.reset()
            
            completion(results, [path: imports])
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}




final class SomeVisitor: SyntaxVisitor {
    var ps = [Key: Val]()
    var ks = [Key: Val]()
    
    init() {
    }
    
    func reset() {
        ps.removeAll()
        ks.removeAll()
    }
    
    func ptargeted(name: String) -> Bool {
           if name.hasSuffix("Presentable") ||
               name.hasSuffix("Interactable") ||
               name.hasSuffix("Routing") ||
               name.hasSuffix("ViewControllable") {
               return true
           }
           
           return false
    }

    func targeted(name: String) -> Bool {
           if name.hasSuffix("Presenter") ||
               name.hasSuffix("Interactor") ||
               name.hasSuffix("Router") ||
               name.hasSuffix("ViewController") {
               return true
           }
           
           return false
    }

    
    func visit(_ current: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let k = current.name // Key(path: path, name: current.name)
        guard ptargeted(name: k) else { return .skipChildren }
        
        let metadata = current.annotationMetadata(with: "@CreateMock")
        let an = metadata != nil
        
        
        let v = Val(acl: current.acl, annotated: an, parents: [])
        ps[k] = v
        return .skipChildren
    }
    
    func visit(_ current: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let k = current.name // Key(path: path, name: current.name)
        guard targeted(name: k) else { return .skipChildren }

        let v = Val(acl: current.acl, annotated: false, parents: current.inheritedTypes)
        ks[k] = v
        return .skipChildren
    }

    func visit(_ current: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let k = current.identifier.description.trimmingCharacters(in: .whitespaces)
        guard targeted(name: k) else { return .skipChildren }

        let acl = current.modifiers?.acl ?? ""
        let list = current.inheritanceClause?.types ?? []
        
        let v = Val(acl: acl, annotated: false, parents: list)
        ks[k] = v
        return .skipChildren
    }

    func visit(_ current: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let k = current.identifier.description.trimmingCharacters(in: .whitespaces)
        guard targeted(name: k) else { return .skipChildren }

        let acl = current.modifiers?.acl ?? ""
        let list = current.inheritanceClause?.types ?? []
        let v = Val(acl: acl, annotated: false, parents: list)
        ks[k] = v
        return .skipChildren
    }
}
