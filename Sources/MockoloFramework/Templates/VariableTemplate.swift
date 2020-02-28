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

//let blacklist = ["PluginizedScope", "Scope"]

func blacklisted(name: String, type: String) -> Bool {
    if name == "path", type == "[String]" {
        return true
    }
    return false
}

func applyVariableTemplate(name: String,
                           type: Type,
                           typeKeys: [String: String]?,
                           staticKind: String,
                           shouldOverride: Bool,
                           accessControlLevelDescription: String) -> String {
    
    let underlyingName = "\(String.underlyingVarPrefix)\(name.capitlizeFirstLetter)"
    let underlyingSetCallCount = "\(name)\(String.setCallCountSuffix)"
    let underlyingVarDefaultVal = type.defaultVal(with: typeKeys) ?? ""
    
    var underlyingType = type.typeName
    if underlyingVarDefaultVal.isEmpty {
        underlyingType = type.underlyingType
    }
    
    let overrideStr = shouldOverride ? "\(String.override) " : ""
    var acl = accessControlLevelDescription
    if !acl.isEmpty {
        acl = acl + " "
    }
    
    let assignVal = underlyingVarDefaultVal.isEmpty ? "" : "= \(underlyingVarDefaultVal)"
    var setCallCountStmt = "\(underlyingSetCallCount) += 1"
    
    var template = ""
    if staticKind.isEmpty, !underlyingVarDefaultVal.isEmpty {
        
        let mockable = acl.contains("public") ? "@Mockable " : "@MockableInternal "
        if !blacklisted(name: name, type: type.typeName) {
            template = """
            \(String.spaces4)\(acl)var \(underlyingSetCallCount): Int { return self._\(name).setCallCount }
            \(String.spaces4)\(mockable)\(acl)\(overrideStr)var \(name): \(type.typeName) = \(underlyingVarDefaultVal)
            """
        } else {
            template = """
            \(String.spaces4)\(acl)var \(underlyingSetCallCount) = 0
            \(String.spaces4)\(acl)\(overrideStr)var \(name): \(type.typeName) \(assignVal) { didSet { \(setCallCountStmt) } }
            """
        }
    } else {

        if staticKind.isEmpty {
            setCallCountStmt = "if \(String.doneInit) { \(underlyingSetCallCount) += 1 }"
        }
        
        let staticStr = staticKind.isEmpty ? "" : "\(staticKind) "
        
        template = """
        \(String.spaces4)\(acl)\(staticStr)var \(underlyingSetCallCount) = 0
        \(String.spaces4)\(staticStr)var \(underlyingName): \(underlyingType) \(assignVal)
        \(String.spaces4)\(acl)\(staticStr)\(overrideStr)var \(name): \(type.typeName) {
        \(String.spaces8)get { return \(underlyingName) }
        \(String.spaces8)set {
        \(String.spaces12)\(underlyingName) = newValue
        \(String.spaces12)\(setCallCountStmt)
        \(String.spaces8)}
        \(String.spaces4)}
        """
    }
    return template
}

func applyRxVariableTemplate(name: String,
                             type: Type,
                             overrideTypes: [String: String]?,
                             typeKeys: [String: String]?,
                             staticKind: String,
                             shouldOverride: Bool,
                             accessControlLevelDescription: String) -> String? {
    if let overrideTypes = overrideTypes, !overrideTypes.isEmpty {
        let (subjectType, subjectVal) = type.parseRxVar(overrides: overrideTypes, overrideKey: name, isInitParam: true)
        if let underlyingSubjectType = subjectType {
            
            let underlyingSubjectName = "\(name)\(String.subjectSuffix)"
            let underlyingSetCallCount = "\(underlyingSubjectName)\(String.setCallCountSuffix)"
            
            var defaultValAssignStr = ""
            if let underlyingSubjectTypeDefaultVal = subjectVal {
                defaultValAssignStr = " = \(underlyingSubjectTypeDefaultVal)"
            } else {
                defaultValAssignStr = ": \(underlyingSubjectType)!"
            }
            
            let acl = accessControlLevelDescription.isEmpty ? "" : accessControlLevelDescription + " "
            let overrideStr = shouldOverride ? "\(String.override) " : ""
            let staticStr = staticKind.isEmpty ? "" : "\(staticKind) "
            let incrementCallCount = "\(underlyingSetCallCount) += 1"
            let setCallCountStmt = staticKind.isEmpty ? "if \(String.doneInit) { \(incrementCallCount) }" : incrementCallCount
            let fallbackName =  "\(String.underlyingVarPrefix)\(name.capitlizeFirstLetter)"
            var fallbackType = type.typeName
            if type.isIUO || type.isOptional {
                fallbackType.removeLast()
            }
            
            let template = """
            \(String.spaces4)\(acl)\(staticStr)var \(underlyingSetCallCount) = 0
            \(String.spaces4)\(staticStr)var \(fallbackName): \(fallbackType)? { didSet { \(setCallCountStmt) } }
            \(String.spaces4)\(acl)\(staticStr)var \(underlyingSubjectName)\(defaultValAssignStr) { didSet { \(setCallCountStmt) } }
            \(String.spaces4)\(acl)\(staticStr)\(overrideStr)var \(name): \(type.typeName) {
            \(String.spaces8)get { return \(fallbackName) ?? \(underlyingSubjectName) }
            \(String.spaces8)set { if let val = newValue as? \(underlyingSubjectType) { \(underlyingSubjectName) = val } else { \(fallbackName) = newValue } }
            \(String.spaces4)}
            """
            
            return template
        }
    }
    
    let typeName = type.typeName
    if let range = typeName.range(of: String.observableVarPrefix), let lastIdx = typeName.lastIndex(of: ">") {
        let typeParamStr = typeName[range.upperBound..<lastIdx]
        let underlyingSubjectName = "\(name)\(String.subjectSuffix)"
        let whichSubject = "\(underlyingSubjectName)Kind"
        let underlyingSetCallCount = "\(underlyingSubjectName)\(String.setCallCountSuffix)"
        let publishSubjectName = underlyingSubjectName
        let publishSubjectType = "\(String.publishSubject)<\(typeParamStr)>"
        let behaviorSubjectName = "\(name)\(String.behaviorSubject)"
        let behaviorSubjectType = "\(String.behaviorSubject)<\(typeParamStr)>"
        let replaySubjectName = "\(name)\(String.replaySubject)"
        let replaySubjectType = "\(String.replaySubject)<\(typeParamStr)>"
        let underlyingObservableName = "\(String.underlyingVarPrefix)\(name.capitlizeFirstLetter)"
        let underlyingObservableType = typeName[typeName.startIndex..<typeName.index(after: lastIdx)]
        let acl = accessControlLevelDescription.isEmpty ? "" : accessControlLevelDescription + " "
        let staticStr = staticKind.isEmpty ? "" : "\(staticKind) "
        let setCallCountStmt = staticStr.isEmpty ? "if \(String.doneInit) { \(underlyingSetCallCount) += 1 }" : "\(underlyingSetCallCount) += 1"
        let overrideStr = shouldOverride ? "\(String.override) " : ""
        
        var template = ""
        let mockable = acl.contains("public") ? "@MockObservable " : "@MockObservableInternal "

        if staticKind.isEmpty, !blacklisted(name: name, type: type.typeName), let underlyingVarDefaultVal = type.defaultVal(with: typeKeys) {
            template = """
            \(String.spaces4)\(acl)\(staticStr)var \(underlyingSetCallCount): Int { return self._\(name).setCallCount }
            \(String.spaces4)\(acl)\(staticStr)var \(publishSubjectName): \(publishSubjectType) { return self._\(name).publishSubject }
            \(String.spaces4)\(acl)\(staticStr)var \(replaySubjectName): \(replaySubjectType) { return self._\(name).replaySubject }
            \(String.spaces4)\(acl)\(staticStr)var \(behaviorSubjectName): \(behaviorSubjectType) { return self._\(name).behaviorSubject }
            \(String.spaces4)\(acl)\(staticStr)var \(underlyingObservableName): \(underlyingObservableType) { return self._\(name).fallback }
            \(String.spaces4)\(mockable)\(acl)\(staticStr)\(overrideStr)var \(name): \(typeName) = \(underlyingVarDefaultVal)
            """
        } else {
            template = """
            \(String.spaces4)\(staticStr)private var \(whichSubject) = 0
            \(String.spaces4)\(acl)\(staticStr)var \(underlyingSetCallCount) = 0
            \(String.spaces4)\(acl)\(staticStr)var \(publishSubjectName) = \(publishSubjectType)() { didSet { \(setCallCountStmt) } }
            \(String.spaces4)\(acl)\(staticStr)var \(replaySubjectName) = \(replaySubjectType).create(bufferSize: 1) { didSet { \(setCallCountStmt) } }
            \(String.spaces4)\(acl)\(staticStr)var \(behaviorSubjectName): \(behaviorSubjectType)! { didSet { \(setCallCountStmt) } }
            \(String.spaces4)\(acl)\(staticStr)var \(underlyingObservableName): \(underlyingObservableType)! { didSet { \(setCallCountStmt) } }
            \(String.spaces4)\(acl)\(staticStr)\(overrideStr)var \(name): \(typeName) {
            \(String.spaces8)get {
            \(String.spaces12)if \(whichSubject) == 0 { return \(publishSubjectName) }
            \(String.spaces12)else if \(whichSubject) == 1 { return \(behaviorSubjectName) }
            \(String.spaces12)else if \(whichSubject) == 2 { return \(replaySubjectName) }
            \(String.spaces12)else { return \(underlyingObservableName) }
            \(String.spaces8)}
            \(String.spaces8)set {
            \(String.spaces12)if let val = newValue as? \(publishSubjectType) { \(whichSubject) = 0; \(publishSubjectName) = val }
            \(String.spaces12)else if let val = newValue as? \(behaviorSubjectType) { \(whichSubject) = 1; \(behaviorSubjectName) = val }
            \(String.spaces12)else if let val = newValue as? \(replaySubjectType) { \(whichSubject) = 2; \(replaySubjectName) = val }
            \(String.spaces12)else { \(whichSubject) = 3; \(underlyingObservableName) = newValue }
            \(String.spaces8)}
            \(String.spaces4)}
            """
        }
    
        return template
    }
    return nil
}




#if MOCK
import RxSwift

@propertyWrapper
public struct MockObservable<Value: ObservableType> where Value.E: Any {

    public var setCallCount: Int = 0
    public var publishSubject = PublishSubject<Value.E>() { didSet { setCallCount += 1} }
    public var replaySubject = ReplaySubject<Value.E>.create(bufferSize: 1) { didSet { setCallCount += 1} }
    public var behaviorSubject: BehaviorSubject<Value.E>! { didSet { setCallCount += 1} }
    public var fallback: Value! { didSet { setCallCount += 1} }
    var whichKind = 0
    
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
    
    public var wrappedValue: Value {
        get {
            if whichKind == 0 { return publishSubject as! Value }
            if whichKind == 1 { return replaySubject as! Value }
            if whichKind == 2 { return behaviorSubject as! Value }
            return fallback
        }

        set {
            if let val = newValue as? PublishSubject<Value.E> {
                publishSubject = val
                whichKind = 0
            }
            else if let val = newValue as? ReplaySubject<Value.E> {
                replaySubject = val
                whichKind = 1
            }
            else if let val = newValue as? BehaviorSubject<Value.E> {
                behaviorSubject = val
                whichKind = 2
            } else {
                fallback = newValue
                whichKind = 3
            }
        }
    }
}


@propertyWrapper
public struct Mockable<Value> {

    public var stored: Value
    public var setCallCount: Int = 0

    public init(wrappedValue: Value) {
        self.stored = wrappedValue
    }
    
    public var wrappedValue: Value {
        get {
            return stored
        }

        set {
            stored = newValue
            setCallCount += 1
        }
    }
}



@propertyWrapper
struct MockObservableInternal<Value: ObservableType> where Value.E: Any {

    var setCallCount: Int = 0
    var publishSubject = PublishSubject<Value.E>() { didSet { setCallCount += 1} }
    var replaySubject = ReplaySubject<Value.E>.create(bufferSize: 1) { didSet { setCallCount += 1} }
    var behaviorSubject: BehaviorSubject<Value.E>! { didSet { setCallCount += 1} }
    var fallback: Value! { didSet { setCallCount += 1} }
    var whichKind = 0
    
    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
    
    var wrappedValue: Value {
        get {
            if whichKind == 0 { return publishSubject as! Value }
            if whichKind == 1 { return replaySubject as! Value }
            if whichKind == 2 { return behaviorSubject as! Value }
            return fallback
        }

        set {
            if let val = newValue as? PublishSubject<Value.E> {
                publishSubject = val
                whichKind = 0
            }
            else if let val = newValue as? ReplaySubject<Value.E> {
                replaySubject = val
                whichKind = 1
            }
            else if let val = newValue as? BehaviorSubject<Value.E> {
                behaviorSubject = val
                whichKind = 2
            } else {
                fallback = newValue
                whichKind = 3
            }
        }
    }
}


@propertyWrapper
struct MockableInternal<Value> {

    var stored: Value
    var setCallCount: Int = 0

    init(wrappedValue: Value) {
        self.stored = wrappedValue
    }
    
    var wrappedValue: Value {
        get {
            return stored
        }

        set {
            stored = newValue
            setCallCount += 1
        }
    }
}


#endif

