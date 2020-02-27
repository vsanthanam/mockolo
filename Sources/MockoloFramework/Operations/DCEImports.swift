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


/*
 
 First, scan all the classes declared, and generate a map: key == class name, val == path, module, used_bit
 
 Second, scan all the classes used -- in var decls, type params, in func/var bodies and globally, and generate a
 used_list of classes
 
 Third, go through first map, check if key and val (key's parents) are in used_map, if not, mark it unused.
 
 Fourth, go through unused_map, remove class decl for each entry.
 
 */

private let vendorlibs = "Search EatsSupport GooglePlaces CocoaAsyncSocket RealtimeEatsSearch EatsSharedProtocols EatsShared EatsUI Octopus OctopusDriver Photos Contacts ConversationalAiGRPC Charts Intents IntensUI JustRideSDK MXLCalendarManagerSwift Photos BraintreeVenmo PayPalDataCollector Box MapLocationSimulating MapDisplayAPI MapDisplaySDKSupport MapDisplayGoogle MapNavigationUI MapDisplayMapKit MapDisplayAPI MapDisplayUber WebKit SwiftProtobuf DifferenceKit Cyborg Concurrency Braintree BraintreePayPal ObjectiveC CryptoSwift Compression CommonCrypto Crashlytics Octopus SnapKit VisionKit Tune TensorFlowWrapper DeviceUtil YogaKit Starscream ResumableAssert zlib signpost os.signpost NIOHPACK GRPC NIO NIOHTTP2 NIOSSL NeedleFoundation Freddy Lottie Zip AppAuth MapsSupport FacebookZero UberMappingNavigating UberMappingRouting ElevateIdl Adyen3DS2"
private let systemlibs = "GameplayKit Accelerate CoreNFC WatchConnectivity AudioToolbox CoreImage CoreMedia CoreText CoreVideo DeviceCheck simd simd.common AuthenticationServices AdSupport MapKit SPMUtility ARKit MessageUI SafariServices StoreKit UserNotifications CoreGraphics MediaPlayer iAd AVKit QuartzCore CoreServices CoreBluetooth CoreLocation CLLocation TwilioVoice CallKit PushKit UIKit CoreMotion CoreLocation Foundation PassKit SceneKit AVFoundation Dispatch ImageIO CardIO GoogleMaps PDFKit NaturalLanguage JavaScriptCore"

private let objcTypes = "FireflyAnimationType: Firefly, UBPushNotificationsRouting: EatsPushNotifications, UBEOutOfServiceNetworkServicing: EatsOutOfService, UBEPendingRatingService: EatsRating"
private let list = (systemlibs + " " + vendorlibs).components(separatedBy: " ")

private func _whitelisted(_ i: String) -> Bool {
    return i.hasSuffix("Objc") || i.contains("Legacy") ||  i.contains("UberMaps") || i.hasPrefix("UB") || i.hasPrefix("Rx") || i.hasPrefix("PermissionManager") || list.contains(i)
}

private func whitelisted(_ i: String) -> Bool {
    if i.contains(".") {
        let comps = i.components(separatedBy: ".").filter {!$0.isEmpty}
        for c in comps {
            let isWhitelisted = _whitelisted(c)
            if isWhitelisted {
                return true
            }
        }
    }
    return _whitelisted(i)
}


public func dceImports(sourceDirs: [String],
                       exclusionSuffixes: [String]? = nil,
                       exclusionSuffixesForUsed: [String]? = nil,
                       outputFilePath: String? = nil,
                       concurrencyLimit: Int? = nil) {

    let p = ParserViaSwiftSyntax()
   
    log("Scan all class decls...")
    let t0 = CFAbsoluteTimeGetCurrent()

    var allDeclMap = [String: [String]]()
    var moduleToDecls = [String: [String]]()
    p.scanDecls(dirs: sourceDirs, exclusionSuffixes: exclusionSuffixes) { (filepath, declMap) in
        for (k, v) in declMap {
            if allDeclMap[k] == nil {
                allDeclMap[k] = []
            }
            allDeclMap[k]?.append(contentsOf: v)
        }
    }
    let t1 = CFAbsoluteTimeGetCurrent()
    log("----", t1-t0)

//    log("Map modules to decls...")
//    for (k, v) in allDeclMap {
//        if moduleToDecls[v.module] == nil {
//            moduleToDecls[v.module] = []
//        }
//        moduleToDecls[v.module]?.append(k)
//    }

    /* TODO: /Users/ellieshin/uber/mirror/ios/libraries/common/DefaultStoreRegistry/DefaultStoreRegistry/Storage+RxExtensions.swift
    needed PresidioFoundation  -- why?

     libraries/feature/Profile/Profile/ProfilePrediction/ProfilePredictionRateLimitStrategy.swift:42:48: error: extra argument 'for' in call
                 .combineLatest(store.element(for: .acceptCount),
                                                   ~^~~~~~~~~~~
     libraries/feature/Profile/Profile/Streams/Voucher/VoucherStream.swift:45:49: error: extra argument 'for' in call
                 .element(for: VoucherStreamModelKey.voucher)
                               ~~~~~~~~~~~~~~~~~~~~~~^~~~~~~

     TODO: import Photos (PHPhotoLibrary, PHAuthorization), Contacts (CNContactStore), ConversationalAiGRPC

     TODO: AudioManagementTesterComponent in prod code in AudioNonCore


     apps/jump/Jump/JumpCore/JumpCore/AppStartup/Steps/RootDependencyStep.swift:58:19: error: method does not override any method from its superclass
     override func execute(input: RootDependencyStepInputType, lifecycle: ApplicationLaunchLifecyle) -> AppComponent {
     ~~~~~~~~      ^
     
     */
    log("Scan used types...")
    var unusedImports = [String: [String]]()
    var unusedImportCounts = [String: Int]()
    var usedDecls = [String: [String: [String]]]()
    var total = 0

    // TODO:
    // libraries/common/SharedUI/SharedUI/Common/LoadingButton.swift needs Realtime: why??
    // override init / AnalyticsMetadata

    p.scanRefs(dirs: sourceDirs, exclusionSuffixes: exclusionSuffixes) { (filepath, refs, imports) in
        var usedImports = [String: Bool]()
        var count = 0
        for i in imports {
            usedImports[i] = whitelisted(i)
        }

        usedDecls[filepath] = [:]
        for r in refs {
            // TODO: handle objc decl

            // TODO: handle nilOrEmpty under operator == (in UberPass)

            // TODO: handle regionStream (extension RegionStrem): the module with RegionStream (TripNonCoreFlow) was not in imports
            // of the ProfilePredictionRateLimitStrategy.swift but it might have been in dependent files, but it got removed, and now
            // needs to be added to the file explcitily

            // TODO: handle KeyValue -- func element<T>(for key:) is in DefaultStoreRegistry. Now needs to be added explcitily.



            if r.hasSuffix("Strings"), let f = r.components(separatedBy: "Strings").first, imports.contains(f) {
                usedImports[f] = true
            }
            if r.hasSuffix("Images"), let f = r.components(separatedBy: "Images").first, imports.contains(f) {
                usedImports[f] = true
            }

            if r == "FireflyAnimationType", imports.contains("Firefly") {
                usedImports["Firefly"] = true
            }

            if (r == "StacktraceReportGeneratorManaging" || r == "StartupReason" || r == "StartupCrashRecovering" || r == "Healthlining" || r == "HealthlineManager" || r.contains("ApplicationStartupReasonReporterNotificationRelay")), imports.contains("Healthline") {
                usedImports["Healthline"] = true
            }
            if r == "AnalyticsMetadata", imports.contains("Realtime") {
                usedImports["Realtime"] = true
            }

            // TODO: when accessing a member, need to import module where the member is declared.
            // e.g. libraries/feature/Profile/Profile/ProfilePrediction/ProfilePrediction: PresidioUtilies for store.element(forKey: .acceptCount)
            if let modules = allDeclMap[r] {
                for m in modules {
                    if imports.contains(m) {
                        usedImports[m] = true
                    } else if m.contains("/") { // can be a path in case module is not found
                        let pcomps = m.components(separatedBy: "/")
                        for p in pcomps {
                            if imports.contains(p) {
                                usedImports[p] = true
                            }
                        }
                    } else {
                        let dots = imports.filter {$0.contains(".")}
                        for d in dots {
                            let dcomps = d.components(separatedBy: ".")
                            if dcomps.contains(m) {
                                usedImports[d] = true
                            }
                        }
                    }
                }
            } else if imports.contains(r) { // sometimes modulename can be used in code block, e.g. PresidioFoundation.DispatchQueue
                usedImports[r] = true
            }

            if let modules = allDeclMap[r] {
                if usedDecls[filepath]?[r] == nil {
                    usedDecls[filepath]?[r] = []
                }
                usedDecls[filepath]?[r]?.append(contentsOf: modules)
            }
        }

        unusedImports[filepath] = []
        for (k, v) in usedImports {
            if !v {
                count += 1
                total += 1
                unusedImports[filepath]?.append(k)
            }
        }
        unusedImportCounts[filepath] = count

        if total % 1000 == 0 {
            log("#", total)
        }
    }
    let t2 = CFAbsoluteTimeGetCurrent()
    log("----", t2-t1)

    log("#Unused imports", total)
    log("Saving stats...")

    let ret = unusedImports.compactMap { (path, unusedlist) -> String? in
        let delta = unusedImportCounts[path] ?? 0
        assert(unusedlist.count == delta)
        if delta != 0 {
//            let used = usedDecls[path]?
//                .map {$0.0 + ": " + Set($0.1).joined(separator: ", ")}
//                .joined(separator: "\n") ?? ""
            return path + "\n" + String(delta) + "\n" + unusedlist.joined(separator: ", ")
        }
        return nil
    }.joined(separator: "\n\n")

    let declstr = allDeclMap.map{ (k, v) -> String in
        let t = """
            \(k):  \(v)
        """
        return t
    }.joined(separator: "\n")

    if let op = outputFilePath {
        try? ret.write(toFile: op, atomically: true, encoding: .utf8)
        try? declstr.write(toFile: op+"-decls", atomically: true, encoding: .utf8)
    }
    let t3 = CFAbsoluteTimeGetCurrent()
    log("----", t3-t2)

    log("Removing unused imports from files...")
    p.removeUnusedImports(dirs: sourceDirs,
                          exclusionSuffixes: exclusionSuffixes,
                          unusedImports: unusedImports) { (path, result) in
                            try? result.write(toFile: path, atomically: true, encoding: .utf8)
    }

    let t4 = CFAbsoluteTimeGetCurrent()
    log("----", t4-t3)

    log("Total (s)", t4-t0)
}

