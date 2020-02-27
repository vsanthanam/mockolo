//
//  SwiftSyntaxExtensions.swift
//  MockoloFramework
//
//  Created by Ellie Shin on 10/29/19.
//

import Foundation
import SwiftSyntax

extension SyntaxParser {
    public static func parse(_ fileData: Data, path: String,
                             diagnosticEngine: DiagnosticEngine? = nil) throws -> SourceFileSyntax {
        // Avoid using `String(contentsOf:)` because it creates a wrapped NSString.
        let source = fileData.withUnsafeBytes { buf in
            return String(decoding: buf.bindMemory(to: UInt8.self), as: UTF8.self)
        }
        return try parse(source: source, filenameForDiagnostics: path,
                         diagnosticEngine: diagnosticEngine)
    }
    
    public static func parse(_ path: String) throws -> SourceFileSyntax {
        guard let fileData = FileManager.default.contents(atPath: path) else {
            fatalError("Retrieving contents of \(path) failed")
        }
        return try parse(fileData, path: path)
    }
}

extension Syntax {
    var offset: Int64 {
        return Int64(self.position.utf8Offset)
    }
    
    var length: Int64 {
        return Int64(self.totalLength.utf8Length)
    }
}

extension AttributeListSyntax {
    var trimmedDescription: String? {
        return self.withoutTrivia().description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ModifierListSyntax {
    var acl: String {
        for modifier in self {
            for token in modifier.tokens {
                switch token.tokenKind {
                case .publicKeyword, .internalKeyword, .privateKeyword, .fileprivateKeyword:
                    return token.text
                default:
                    // For some reason openKeyword option is not available in TokenKind so need to address separately
                    if token.text == String.open {
                        return token.text
                    }
                    return ""
                }
            }
        }
        return ""
    }
    
    var isStatic: Bool {
        return self.tokens.filter {$0.tokenKind == .staticKeyword }.count > 0
    }
    
    var isRequired: Bool {
        return self.tokens.filter {$0.text == String.required }.count > 0
    }
    
    var isConvenience: Bool {
        return self.tokens.filter {$0.text == String.convenience }.count > 0
    }
    
    var isOverride: Bool {
        return self.tokens.filter {$0.text == String.override }.count > 0
    }
    
    var isFinal: Bool {
        return self.tokens.filter {$0.text == String.final }.count > 0
    }
    
    var isPrivate: Bool {
        return self.tokens.filter {$0.tokenKind == .privateKeyword || $0.tokenKind == .fileprivateKeyword }.count > 0
    }
    
    var isPublic: Bool {
        return self.tokens.filter {$0.tokenKind == .publicKeyword }.count > 0
    }
}

extension TypeInheritanceClauseSyntax {
    var types: [String] {
        var list = [String]()
        for element in self.inheritedTypeCollection {
            if let elementName = element.firstToken?.text {
                list.append(elementName)
            }
        }
        return list
    }
    
    var typesDescription: String {
        return self.inheritedTypeCollection.description
    }
}

extension MemberDeclListItemSyntax {
    private func validateMember(_ modifiers: ModifierListSyntax?, _ declType: DeclType, processed: Bool) -> Bool {
        if let mods = modifiers {
            if !processed && mods.isPrivate || mods.isStatic && declType == .classType {
                return false
            }
        }
        return true
    }
    
    private func validateInit(_ initDecl: InitializerDeclSyntax, _ declType: DeclType, processed: Bool) -> Bool {
        var isRequired = false
        if let modifiers = initDecl.modifiers {
            isRequired = modifiers.isRequired
        }
        if processed {
            return isRequired
        }
        var isConvenience = false
        var isPrivate = false
        if let modifiers = initDecl.modifiers {
            isConvenience = modifiers.isConvenience
            isPrivate = modifiers.isPrivate
        }
        
        if isConvenience || isPrivate {
            return false
        }
        return true
    }
    
    private func memberAcl(_ modifiers: ModifierListSyntax?, _ encloserAcl: String, _ declType: DeclType) -> String {
        if declType == .protocolType {
            return encloserAcl
        }
        return modifiers?.acl ?? ""
    }

    func transformToModel(with encloserAcl: String, declType: DeclType, metadata: AnnotationMetadata?, processed: Bool) -> (Model, String?, Bool)? {
        if let varMember = self.decl as? VariableDeclSyntax {
            if validateMember(varMember.modifiers, declType, processed: processed) {
                let acl = memberAcl(varMember.modifiers, encloserAcl, declType)
                if let item = varMember.models(with: acl, declType: declType, overrides: metadata?.varTypes, processed: processed).first {
                    return (item, varMember.attributes?.trimmedDescription, false)
                }
            }
        } else if let funcMember = self.decl as? FunctionDeclSyntax {
            if validateMember(funcMember.modifiers, declType, processed: processed) {
                let acl = memberAcl(funcMember.modifiers, encloserAcl, declType)
                let item = funcMember.model(with: acl, declType: declType, processed: processed)
                return (item, funcMember.attributes?.trimmedDescription, false)
            }
        } else if let subscriptMember = self.decl as? SubscriptDeclSyntax {
            if validateMember(subscriptMember.modifiers, declType, processed: processed) {
                let acl = memberAcl(subscriptMember.modifiers, encloserAcl, declType)
                let item = subscriptMember.model(with: acl, declType: declType, processed: processed)
                return (item, subscriptMember.attributes?.trimmedDescription, false)
            }
        } else if let initMember = self.decl as? InitializerDeclSyntax {
            if validateInit(initMember, declType, processed: processed) {
                let acl = memberAcl(initMember.modifiers, encloserAcl, declType)
                let item = initMember.model(with: acl, declType: declType, processed: processed)
                return (item, initMember.attributes?.trimmedDescription, true)
            }
        } else if let patMember = self.decl as? AssociatedtypeDeclSyntax {
            let acl = memberAcl(patMember.modifiers, encloserAcl, declType)
            let item = patMember.model(with: acl, declType: declType, overrides: metadata?.typeAliases, processed: processed)
            return (item, patMember.attributes?.trimmedDescription, false)
        } else if let taMember = self.decl as? TypealiasDeclSyntax {
            let acl = memberAcl(taMember.modifiers, encloserAcl, declType)
            let item = taMember.model(with: acl, declType: declType, overrides: metadata?.typeAliases, processed: processed)
            return (item, taMember.attributes?.trimmedDescription, false)
        } else if let ifMacroMember = self.decl as? IfConfigDeclSyntax {
            let (item, attr, initFlag) = ifMacroMember.model(with: encloserAcl, declType: declType, metadata: metadata, processed: processed)
            return (item, attr, initFlag)
        }
        
        return nil
    }
}

extension MemberDeclListSyntax {
    var hasBlankInit: Bool {
        for member in self {
            if let varMember = member.decl as? VariableDeclSyntax {
                for v in varMember.bindings {
                    if let name = v.pattern.firstToken?.text {
                        if name == String.hasBlankInit {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    func memberData(with encloserAcl: String, declType: DeclType, metadata: AnnotationMetadata?, processed: Bool) -> EntityNodeSubContainer {
        var attributeList = [String]()
        var memberList = [Model]()
        var hasInit = false

        for m in self {
            if let (item, attr, initFlag) = m.transformToModel(with: encloserAcl, declType: declType, metadata: metadata, processed: processed) {
                memberList.append(item)
                if let attrDesc = attr {
                    attributeList.append(attrDesc)
                }
                hasInit = hasInit || initFlag
            }
        }
        return EntityNodeSubContainer(attributes: attributeList, members: memberList, hasInit: hasInit)
    }
}

extension IfConfigDeclSyntax {
    func model(with encloserAcl: String, declType: DeclType, metadata: AnnotationMetadata?, processed: Bool) -> (Model, String?, Bool) {
        var subModels = [Model]()
        var attrDesc: String?
        var hasInit = false

        var name = ""
        for cl in self.clauses {
            if let desc = cl.condition?.description, let list = cl.elements as? MemberDeclListSyntax {
                name = desc
                
                for element in list {
                    if let (item, attr, initFlag) = element.transformToModel(with: encloserAcl, declType: declType, metadata: metadata, processed: processed) {
                        subModels.append(item)
                        if let attr = attr, attr.contains(String.available) {
                            attrDesc = attr
                        }
                        hasInit = hasInit || initFlag
                    }
                }
            }
        }
        
        let macroModel = IfMacroModel(name: name, offset: self.offset, entities: subModels)
        return (macroModel, attrDesc, hasInit)
    }
}

extension EnumDeclSyntax: EntityBase {
    var name: String {
        return identifier.text.trimmingCharacters(in: .whitespaces)
    }
    var declType: DeclType {
        return .enumType
    }
    var typeComponents: [String] {
        return inheritanceClause?.types ?? []
    }
}

extension StructDeclSyntax: EntityBase {
    var name: String {
        return identifier.text.trimmingCharacters(in: .whitespaces)
    }
    var declType: DeclType {
        return .structType
    }

    var typeComponents: [String] {
        return inheritanceClause?.types ?? []
    }
}

extension TypealiasDeclSyntax: EntityBase {
    var name: String {
        return identifier.text.trimmingCharacters(in: .whitespaces)
    }
    var declType: DeclType {
        return .typealiasType
    }
    var typeComponents: [String] {
        return initializer?.value.tokens.userDefinedTypes ?? []
    }
}

extension ExtensionDeclSyntax: EntityBase {
    var name: String {
        return extendedType.description.trimmingCharacters(in: .whitespaces)
    }
    var declType: DeclType {
        return .extensionType
    }

    var typeComponents: [String] {
        return [inheritedTypes, genericTypes].flatMap{$0}
    }

    var genericTypes: [String] {
        return genericWhereClause?.tokens.userDefinedTypes ?? []
    }

    var inheritedTypes: [String] {
        return inheritanceClause?.types ?? []
    }
}

extension ProtocolDeclSyntax: EntityNode {
    var name: String {
        return identifier.text.trimmingCharacters(in: .whitespaces)
    }

    var typeComponents: [String] {
        return [inheritedTypes, genericTypes].flatMap{$0}
    }

    var acl: String {
        return self.modifiers?.acl ?? ""
    }
    
    var declType: DeclType {
        return .protocolType
    }
    
    var isPrivate: Bool {
        return self.modifiers?.isPrivate ?? false
    }
    
    var inheritedTypes: [String] {
        return inheritanceClause?.types ?? []
    }

    var genericTypes: [String] {
        return genericWhereClause?.tokens.userDefinedTypes ?? []
    }

    var attributesDescription: String {
        self.attributes?.trimmedDescription ?? ""
    }
    
    var offset: Int64 {
        return Int64(self.position.utf8Offset)
    }
    
    func annotationMetadata(with annotation: String) -> AnnotationMetadata? {
        return leadingTrivia?.annotationMetadata(with: annotation)
    }
    
    var hasBlankInit: Bool {
        return false
    }
    
    func subContainer(metadata: AnnotationMetadata?, declType: DeclType, path: String?, data: Data?, isProcessed: Bool) -> EntityNodeSubContainer {
        return self.members.members.memberData(with: acl, declType: declType, metadata: metadata, processed: isProcessed)
    }
}

extension ClassDeclSyntax: EntityNode {
    var name: String {
        return identifier.text.trimmingCharacters(in: .whitespaces)
    }

    var typeComponents: [String] {
        return [inheritedTypes, genericTypes].flatMap{$0}
    }

    var acl: String {
        return self.modifiers?.acl ?? ""
    }
    
    var declType: DeclType {
        return .classType
    }
    
    var inheritedTypes: [String] {
        return inheritanceClause?.types ?? []
    }

    var genericTypes: [String] {
        return [genericParameterClause?.tokens.userDefinedTypes, genericWhereClause?.tokens.userDefinedTypes].compactMap{$0}.flatMap{$0}
    }

    var attributesDescription: String {
        self.attributes?.trimmedDescription ?? ""
    }
    
    var offset: Int64 {
        return Int64(self.position.utf8Offset)
    }
    
    var isFinal: Bool {
        return self.modifiers?.isFinal ?? false
    }
    
    var isPrivate: Bool {
        return self.modifiers?.isPrivate ?? false
    }
    
    var isPublic: Bool {
        return self.modifiers?.isPublic ?? false
    }
    
    var hasBlankInit: Bool {
        return self.members.members.hasBlankInit
    }
    
    func annotationMetadata(with annotation: String) -> AnnotationMetadata? {
        return leadingTrivia?.annotationMetadata(with: annotation)
    }
    
    func subContainer(metadata: AnnotationMetadata?, declType: DeclType, path: String?, data: Data?, isProcessed: Bool) -> EntityNodeSubContainer {
        return self.members.members.memberData(with: acl, declType: declType, metadata: nil, processed: isProcessed)
    }
}

extension VariableDeclSyntax: EntityBase {
    var name: String {
        let ret = bindings.compactMap { $0.pattern.firstToken?.text }
        if let first = ret.first {
            return first
        }
        return .unknownVal
    }
    var declType: DeclType {
        return .varType
    }
    var typeComponents: [String] {
        let ret = bindings.compactMap { $0.typeAnnotation?.type.tokens.userDefinedTypes }
        return ret.flatMap{$0}
    }

    func models(with acl: String, declType: DeclType, overrides: [String: String]?, processed: Bool) -> [Model] {
        // Detect whether it's static
        var isStatic = false
        if let modifiers = self.modifiers {
            isStatic = modifiers.isStatic
        }
        
        // Need to access pattern bindings to get name, type, and other info of a var decl
        let varmodels = self.bindings.compactMap { (v: PatternBindingSyntax) -> Model in
            let name = v.pattern.firstToken?.text ?? String.unknownVal
            var typeName = ""
            var potentialInitParam = false
            
            // Get the type info and whether it can be a var param for an initializer
            if let vtype = v.typeAnnotation?.type.description.trimmingCharacters(in: .whitespaces) {
                potentialInitParam = name.canBeInitParam(type: vtype, isStatic: isStatic)
                typeName = vtype
            }
            
            let varmodel = VariableModel(name: name,
                                         typeName: typeName,
                                         acl: acl,
                                         encloserType: declType,
                                         isStatic: isStatic,
                                         canBeInitParam: potentialInitParam,
                                         offset: v.offset,
                                         length: v.length,
                                         overrideTypes: overrides,
                                         modelDescription: self.description,
                                         processed: processed)
            return varmodel
        }
        return varmodels
    }
}

extension SubscriptDeclSyntax: EntityBase {
    var name: String {
        return self.subscriptKeyword.text
    }
    var declType: DeclType {
        return .subscriptType
    }
    var typeComponents: [String] {
        var ret = genericTypes
        ret.append(result.returnType.description)
        return ret
    }

    var genericTypes: [String] {
        return genericParameterClause?.genericParameterList.tokens.userDefinedTypes ?? []
    }

    func model(with acl: String, declType: DeclType, processed: Bool) -> Model {
        var isStatic = false
        if let modifiers = self.modifiers {
            isStatic = modifiers.isStatic
        }
        
        let params = self.indices.parameterList.compactMap { $0.model(inInit: false, declType: declType) }
        let genericTypeParams = self.genericParameterClause?.genericParameterList.compactMap { $0.model(inInit: false) } ?? []
        
        let subscriptModel = MethodModel(name: self.subscriptKeyword.text,
                                         typeName: self.result.returnType.description,
                                         kind: .subscriptKind,
                                         encloserType: declType,
                                         acl: acl,
                                         genericTypeParams: genericTypeParams,
                                         params: params,
                                         throwsOrRethrows: "",
                                         isStatic: isStatic,
                                         offset: self.offset,
                                         length: self.length,
                                         modelDescription: self.description,
                                         processed: processed)
        return subscriptModel
    }
}

extension FunctionDeclSyntax: EntityBase {
    var name: String {
        return self.identifier.description.trimmingCharacters(in: .whitespaces)
    }
    var declType: DeclType {
        return .funcType
    }
    var typeComponents: [String] {
        var ret = genericTypes
        ret.append(contentsOf: paramTypes)
        if let t = signature.output?.returnType.description {
            ret.append(t)
        }
        return ret
    }

    var genericTypes: [String] {
        return [genericParameterClause?.genericParameterList.tokens.userDefinedTypes,
                genericWhereClause?.tokens.userDefinedTypes].compactMap{$0}.flatMap{$0}
    }

    var paramTypes: [String] {
        return signature.input.parameterList.tokens.userDefinedTypes
    }

    func model(with acl: String, declType: DeclType, processed: Bool) -> Model {
        var isStatic = false
        if let modifiers = self.modifiers {
            isStatic = modifiers.isStatic
        }
        
        let params = self.signature.input.parameterList.compactMap { $0.model(inInit: false, declType: declType) }
        let genericTypeParams = self.genericParameterClause?.genericParameterList.compactMap { $0.model(inInit: false) } ?? []
        
        let funcmodel = MethodModel(name: self.identifier.description,
                                    typeName: self.signature.output?.returnType.description ?? "",
                                    kind: .funcKind,
                                    encloserType: declType,
                                    acl: acl,
                                    genericTypeParams: genericTypeParams,
                                    params: params,
                                    throwsOrRethrows: self.signature.throwsOrRethrowsKeyword?.text ?? "",
                                    isStatic: isStatic,
                                    offset: self.offset,
                                    length: self.length,
                                    modelDescription: self.description,
                                    processed: processed)
        return funcmodel
    }
}

extension InitializerDeclSyntax {
    func isRequired(with declType: DeclType) -> Bool {
        if declType == .protocolType {
            return true
        } else if declType == .classType {
            if let modifiers = self.modifiers {
                
                if modifiers.isConvenience {
                    return false
                }
                return modifiers.isRequired
            }
        }
        return false
    }
    
    func model(with acl: String, declType: DeclType, processed: Bool) -> Model {
        let requiredInit = isRequired(with: declType)
        
        let params = self.parameters.parameterList.compactMap { $0.model(inInit: true, declType: declType) }
        let genericTypeParams = self.genericParameterClause?.genericParameterList.compactMap { $0.model(inInit: true) } ?? []
        
        return MethodModel(name: "init",
                           typeName: "",
                           kind: .initKind(required: requiredInit),
                           encloserType: declType,
                           acl: acl,
                           genericTypeParams: genericTypeParams,
                           params: params,
                           throwsOrRethrows: self.throwsOrRethrowsKeyword?.text ?? "",
                           isStatic: false,
                           offset: self.offset,
                           length: self.length,
                           modelDescription: self.description,
                           processed: processed)
    }
    
}


extension GenericParameterSyntax {
    func model(inInit: Bool) -> ParamModel {
        return ParamModel(label: "",
                          name: self.name.text,
                          typeName: self.inheritedType?.description ?? "",
                          isGeneric: true,
                          inInit: inInit,
                          needVarDecl: false,
                          offset: self.offset,
                          length: self.length)
    }
    
}

extension FunctionParameterSyntax {
    func model(inInit: Bool, declType: DeclType) -> ParamModel {
        var label = ""
        var name = ""
        // Get label and name of args
        if let first = self.firstName?.text {
            if let second = self.secondName?.text {
                label = first
                name = second
            } else {
                if first == "_" {
                    label = first
                    name = first + "arg"
                } else {
                    name = first
                }
            }
        }
        
        // Variadic args are not detected in the parser so need to manually look up
        var type = self.type?.description ?? ""
        if self.description.contains(type + "...") {
            type.append("...")
        }
        
        return ParamModel(label: label,
                          name: name,
                          typeName: type,
                          isGeneric: false,
                          inInit: inInit,
                          needVarDecl: declType == .protocolType,
                          offset: self.offset,
                          length: self.length)
    }
    
}

extension AssociatedtypeDeclSyntax {
    func model(with acl: String, declType: DeclType, overrides: [String: String]?, processed: Bool) -> Model {
        // Get the inhertied type for an associated type if any
        var t = self.inheritanceClause?.typesDescription ?? ""
        t.append(self.genericWhereClause?.description ?? "")
        
        return TypeAliasModel(name: self.identifier.text,
                              typeName: t,
                              acl: acl,
                              encloserType: declType,
                              overrideTypes: overrides,
                              offset: self.offset,
                              length: self.length,
                              modelDescription: self.description,
                              processed: processed)
    }
}


extension TypealiasDeclSyntax {
    func model(with acl: String, declType: DeclType, overrides: [String: String]?, processed: Bool) -> Model {
        return TypeAliasModel(name: self.identifier.text,
                              typeName: self.initializer?.value.description ?? "",
                              acl: acl,
                              encloserType: declType,
                              overrideTypes: overrides,
                              offset: self.offset,
                              length: self.length,
                              modelDescription: self.description,
                              useDescription: true,
                              processed: processed)

    }
}

final class EntityVisitor: SyntaxVisitor {
    var entities: [Entity] = []
    var imports: [String] = []
    let annotation: String
    let path: String
    init(_ path: String, annotation: String = "") {
        self.path = path
        self.annotation = annotation
    }
    
    func reset() {
        entities = []
        imports = []
    }
    
    func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let metadata = node.annotationMetadata(with: annotation)
        if let ent = Entity.node(with: node, path: path, isPrivate: node.isPrivate, isFinal: false, metadata: metadata, processed: false) {
            entities.append(ent)
        }
        return .skipChildren
    }
    
    func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.hasSuffix("Mock") {
            // this mock class node must be public else wouldn't have compiled before
            if let ent = Entity.node(with: node, path: path, isPrivate: node.isPrivate, isFinal: false, metadata: nil, processed: true) {
                entities.append(ent)
            }
        } else {
            let metadata = node.annotationMetadata(with: annotation)
            if let ent = Entity.node(with: node, path: path, isPrivate: node.isPrivate, isFinal: node.isFinal, metadata: metadata, processed: false) {
                entities.append(ent)
            }
        }
        return .skipChildren
    }
    
    func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        if let ret = node.path.firstToken?.text {
            let desc = node.importTok.text + " " + ret
            imports.append(desc)
        }
        return .visitChildren
    }
}

extension Trivia {
    // This parses arguments in annotation which can be used to override certain types.
    //
    // E.g. given /// @mockable(typealias: T = Any; U = AnyObject), it returns
    // a dictionary: [T: Any, U: AnyObject] which will be used to override inhertied types
    // of typealias decls for T and U.
    private func metadata(with annotation: String, in val: String) -> AnnotationMetadata? {
        if val.contains(annotation) {
            let comps = val.components(separatedBy: annotation)
            var ret = AnnotationMetadata()
            if var argsStr = comps.last, !argsStr.isEmpty {
                if argsStr.hasPrefix("(") {
                    argsStr.removeFirst()
                }
                if argsStr.hasSuffix(")") {
                    argsStr.removeLast()
                }
                if argsStr.contains(String.typealiasColon), let subStr = argsStr.components(separatedBy: String.typealiasColon).last, !subStr.isEmpty {
                    ret.typeAliases = subStr.arguments(with: .annotationArgDelimiter)
                }
                if argsStr.contains(String.moduleColon), let subStr = argsStr.components(separatedBy: String.moduleColon).last, !subStr.isEmpty {
                    let val = subStr.arguments(with: .annotationArgDelimiter)
                    ret.module = val?[.prefix]
                }
                if argsStr.contains(String.rxColon), let subStr = argsStr.components(separatedBy: String.rxColon).last, !subStr.isEmpty {
                    ret.varTypes = subStr.arguments(with: .annotationArgDelimiter)
                }
                if argsStr.contains(String.varColon), let subStr = argsStr.components(separatedBy: String.varColon).last, !subStr.isEmpty {
                    if let val = subStr.arguments(with: .annotationArgDelimiter) {
                        if ret.varTypes == nil {
                            ret.varTypes = val
                        } else {
                            ret.varTypes?.merge(val, uniquingKeysWith: {$1})
                        }
                    }
                }
            }
            return ret
        }
        return nil
    }
    
    // Looks up an annotation (e.g. /// @mockable) and its arguments if any.
    // See metadata(with:, in:) for more info on the annotation arguments.
    func annotationMetadata(with annotation: String) -> AnnotationMetadata? {
        guard !annotation.isEmpty else { return nil }
        var ret: AnnotationMetadata?
        for i in 0..<count {
            let trivia = self[i]
            switch trivia {
            case .docLineComment(let val):
                ret = metadata(with: annotation, in: val)
                if ret != nil {
                    return ret
                }
            case .docBlockComment(let val):
                ret = metadata(with: annotation, in: val)
                if ret != nil {
                    return ret
                }
            default:
                continue
            }
        }
        return nil
    }
}

extension TokenSyntax {
    var stringToken: String? {
        return text.isAlphanumeric ? text : nil
    }

    var userDefinedType: String? {
        guard !self.text.contains("-"), !self.text.contains(","), !self.text.contains(" ")  else {return nil}
        var typename = self.text
        let isType = typename.first?.isUppercase ?? false
        
        // If no default val found, it's potentially used, so add it to used types
        if isType {
            if text.contains("Mock"), let t = text.components(separatedBy: "Mock").first {
                typename = t
            } else if let _ = Type(typename).defaultSingularVal(isInitParam: false) {
                return nil
            }
            return typename
        }
        return nil
    }
}

extension TokenSequence {
    var tokenList: [String] {
        let ret = self.compactMap { $0.stringToken }
        return ret
    }
    var userDefinedTypes: [String] {
        let ret = self.compactMap { $0.userDefinedType }
        return ret
    }
}



// MARK - used for cleanup

final class CleanerVisitor: SyntaxVisitor {
    let annotation: String
    let pass: Int
    let root: SourceFileSyntax
    let path: String
    let converter: SourceLocationConverter
    let charset: CharacterSet
    var usedTypes = [String]()
    var protocolMap = [String: Entry]()
    
    init(annotation: String, path: String, root: SourceFileSyntax) {
        self.annotation = annotation
        self.path = path
        self.root = root
        self.converter = SourceLocationConverter(file: path, tree: root)
        self.pass = annotation.isEmpty ? 1 : 0
        self.charset = CharacterSet(arrayLiteral: "!", "?").union(.whitespaces)
    }
    
    func reset() {
        usedTypes.removeAll()
        protocolMap.removeAll()
    }

    func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
        if pass == 1 {
            if let item = node.item as? ClassDeclSyntax {
                let ret = [item.inheritanceClause?.inheritedTypeCollection.tokens.userDefinedTypes,
                           item.genericParameterClause?.tokens.userDefinedTypes,
                           item.genericWhereClause?.tokens.userDefinedTypes,
                           item.members.tokens.userDefinedTypes].compactMap{$0}.flatMap{$0}
                
                usedTypes.append(contentsOf: ret)
                return .skipChildren
            }
        }
        if pass == 0 {
            
            if let item = node.item as? ProtocolDeclSyntax {
                let metadata = item.annotationMetadata(with: annotation)
                var docloc = (0, 0)
                if metadata != nil {
                    let loc = node.startLocation(converter: converter)
                    if let l = loc.line, let c = loc.column {
                        let pos = converter.position(ofLine: l, column: c)
                        if let len = node.leadingTrivia?.sourceLength {
                            let end = pos.utf8Offset
                            let start = end - len.utf8Length
                            docloc = (start, end)
                        }
                    }
                }
                
                let parents = item.inheritedTypes.filter{$0 != "AnyObject" && $0 != "class" && $0 != "Any"}
                protocolMap[item.name] = Entry(path: path, module: path.module, parents: parents, annotated: metadata != nil, docLoc: docloc)
                
                
                let ret = [item.inheritanceClause?.inheritedTypeCollection.tokens.userDefinedTypes,
                           item.genericWhereClause?.tokens.userDefinedTypes,
                           item.members.tokens.userDefinedTypes].compactMap{$0}.flatMap{$0}
                usedTypes.append(contentsOf: ret)
                
                return .skipChildren
            }
            
            if let item = node.item as? ExtensionDeclSyntax {
                let ret = [item.inheritanceClause?.inheritedTypeCollection.tokens.userDefinedTypes,
                           item.genericWhereClause?.tokens.userDefinedTypes,
                           item.members.tokens.userDefinedTypes].compactMap{$0}.flatMap{$0}
                usedTypes.append(contentsOf: ret)
                return .skipChildren
            }
        }
        
        if pass == 1 {
            let ret = node.item.tokens.userDefinedTypes
            usedTypes.append(contentsOf: ret)
            return .skipChildren
        }
        
        return .visitChildren
    }
}


struct DeclKey: Hashable {
    let name: String
    //    let path: String
    //
    //    func hash(into hasher: inout Hasher) {
    //        hasher.combine(name)
    //        hasher.combine(path)
    //    }
}

final class DeclVisitor: SyntaxVisitor {
    var declMap = [String: [String]]()
    var path: String
    var module: String
    init(_ path: String) {
        self.path = path
        // TODO: need to get modules as input to handle smth like ConversationalAiGRPC
        if path.module.isEmpty {
            self.module = path
        } else {
            self.module = path.module
        }
    }

    func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {

        if let item = node.item as? EntityBase {
            if declMap[item.name] == nil {
                declMap[item.name] = []
            }

            // TODO: for all decls, add if non-private
            declMap[item.name]?.append(module)
        }
        return .skipChildren
    }
}



final class RefVisitor: SyntaxVisitor {
    var imports = [String]()
    var refs = [String]()
    var path: String
    var module: String
    init(_ path: String) {
        self.path = path
        self.module = path.module
    }
    func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
        if let item = node.item as? ImportDeclSyntax {
            if item.attributes == nil, item.importKind == nil {
                let str = item.path.description.trimmingCharacters(in: .whitespaces)
                imports.append(str)
            }
        } else {
            // TODO: use FunctionCallExpr VarCallExpr instead of tokens
            refs.append(contentsOf: node.tokens.tokenList)
        }
        return .skipChildren
    }
}

public final class ImportRemover: SyntaxRewriter {
    let unused: [String]
    public init(_ path: String, unusedModules: [String]?) {
        self.unused = unusedModules ?? []
    }
    override public func visit(_ node: ImportDeclSyntax) -> DeclSyntax {
        var remove = false
        let str = node.path.description.trimmingCharacters(in: .whitespaces)
        if unused.contains(str) {
            remove = true
        } else {
            for t in node.path.tokens {
                if unused.contains(t.text) {
                    remove = true
                }
            }
        }

        if remove {
            if let trivia = node.importTok.leadingTrivia {
                let t = SyntaxFactory.makeUnknown("", leadingTrivia: trivia, trailingTrivia: Trivia(pieces: []))
                return SyntaxFactory.makeImportDecl(attributes: nil, modifiers: nil, importTok: t, importKind: nil, path: SyntaxFactory.makeAccessPath([]))
            } else {
                return SyntaxFactory.makeBlankImportDecl()
            }
        }

        return super.visit(node)
    }
}


public final class CleanerWriter: SyntaxRewriter {
    var k = 0
    var p = 0
    public func reset() {
        k = 0
        p = 0
    }
    override public func visit(_ node: ProtocolDeclSyntax) -> DeclSyntax {
        p += 1
        return super.visit(node)
    }
    override public func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        k += 1
        return super.visit(node)
    }
}
