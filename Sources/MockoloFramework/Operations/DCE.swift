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


public func dce(sourceDirs: [String],
                exclusionSuffixes: [String]? = nil,
                exclusionSuffixesForUsed: [String]? = nil,
                outputFilePath: String? = nil,
                concurrencyLimit: Int? = nil) {

    let prs = ParserViaSwiftSyntax()
    var nk = 0
    var np = 0
    let u = CFAbsoluteTimeGetCurrent()

    prs.stats(dirs: sourceDirs,
              exclusionSuffixes: exclusionSuffixes) { (k, p) in
                nk += k
                np += p
    }
    let u1 = CFAbsoluteTimeGetCurrent()
    log(np, nk, u1-u)

    log("Scanning...")
    let p = ParserViaSourceKit()
    let t = CFAbsoluteTimeGetCurrent()
    var pc = 0
    var kc = 0

    p.stats(dirs: sourceDirs,
            exclusionSuffixes: exclusionSuffixes) { (p, k) in
                pc += p
                kc += k
    }
    let t0 = CFAbsoluteTimeGetCurrent()
    log("Total", pc, kc, t0-t)
    return


    log("Scan all class decls...")
    var results = [String: Val]()
    p.scanDecls(dirs: sourceDirs, exclusionSuffixes: exclusionSuffixes) { (subResults: [String : Val]) in
        for (k, v) in subResults {
            results[k] = v
        }
    }
    let t1 = CFAbsoluteTimeGetCurrent()
    log("--", t1-t0)
    
    log("Scan used class decls...")
    var usedMap = [String: Bool]()
    p.scanUsedDecls(dirs: sourceDirs, exclusionSuffixes: exclusionSuffixesForUsed) { (subResults: [String]) in
        for r in subResults {
            usedMap[r] = false
        }
    }
    let t2 = CFAbsoluteTimeGetCurrent()
    log("--", t2-t1)
    
    log("Filter unused decls...")
    var unusedMap = [String: Val]()
    for (k, v)  in results {        
        if let _ = usedMap[k] {
            for p in v.parents {
                results[p]?.used = true
            }
        }
    }

    for (k, v)  in results {
        if let _ = usedMap[k] {
            // used
        } else if v.used { // this is needed for parents of the type k
            // used
        } else {
            unusedMap[k] = v
        }
    }


    let t3 = CFAbsoluteTimeGetCurrent()
    log("--", t3-t2)
    
    log("Save results...")
    if let outputFilePath = outputFilePath {
        let used = usedMap.map {"\($0.key)"}.joined(separator: ", ")
        let ret = unusedMap.map {"\($0.key): \($0.value.path)"}.joined(separator: "\n")

        try? used.write(toFile: outputFilePath+"-used", atomically: true, encoding: .utf8)
        try? ret.write(toFile: outputFilePath+"-ret", atomically: true, encoding: .utf8)
        log(" to ", outputFilePath)
    }
    let t4 = CFAbsoluteTimeGetCurrent()
    log("--", t4-t3)
    let paths = unusedMap.values.flatMap{$0.path}
    let pathSet = Set(paths)
    let dpaths = results.values.flatMap{$0.path}
    let dpathSet = Set(dpaths)
    log("#Declared", results.count, "#Paths with unused classes", dpathSet.count)
    log("#Used", usedMap.count)
    log("#Unused", unusedMap.count, "#Paths with unused classes", pathSet.count)


    let limit = concurrencyLimit ?? 12
    let sema = DispatchSemaphore(value: limit)
    let dceq = DispatchQueue(label: "dce-q", qos: DispatchQoS.userInteractive, attributes: DispatchQueue.Attributes.concurrent)

    p.removeUnusedDecls(declMap: unusedMap, queue: dceq, semaphore: sema) { (d: Data, url: URL) in
        try? d.write(to: url)
    }
    let t5 = CFAbsoluteTimeGetCurrent()
    log("Removed unused decls", t5-t4)


    var testsDeleted = 0
    p.updateTests(dirs: sourceDirs, unusedMap: unusedMap, queue: dceq, semaphore: sema) { (d: Data, url: URL, deleteCount: Int, deleteFile: Bool) in
        testsDeleted += deleteCount
        if deleteFile {
            try? FileManager.default.removeItem(at: url)
        } else {
            try? d.write(to: url)
        }
    }
    let t6 = CFAbsoluteTimeGetCurrent()
    log("Removed tests using unused classes", testsDeleted, t6-t5)

    log("Total (s)", t6-t0)
}

