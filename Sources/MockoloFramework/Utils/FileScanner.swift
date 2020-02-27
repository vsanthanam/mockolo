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

public var staticNumThreads: Int? = nil

public func utilScan(dirs: [String],
                     numThreads: Int? = nil,
                     block: @escaping (_ path: String, _ lock: NSLock?) -> ()) {
    
    var queue: DispatchQueue?
    var semaphore: DispatchSemaphore?
    
    if staticNumThreads == nil || (staticNumThreads ?? 0) > 1 {
        let limit = staticNumThreads ?? 12
        semaphore = DispatchSemaphore(value: limit)
        queue = DispatchQueue(label: "dce-q", qos: DispatchQoS.userInteractive, attributes: DispatchQueue.Attributes.concurrent)
    }
    
    if let queue = queue {
        let lock = NSLock()
        scanPaths(dirs) { filePath in
            _ = semaphore?.wait(timeout: DispatchTime.distantFuture)
            queue.async {
                block(filePath, lock)
                semaphore?.signal()
            }
        }
        // Wait for queue to drain
        queue.sync(flags: .barrier) {}
    } else {
        scanPaths(dirs) { filePath in
            block(filePath, nil)
        }
    }
}

public func utilScan(files: [String],
                     numThreads: Int? = nil,
                     block: @escaping (_ path: String, _ lock: NSLock?) -> ()) {
    
    var queue: DispatchQueue?
    var semaphore: DispatchSemaphore?
    if numThreads == nil || (numThreads ?? 0) > 1 {
        let limit = numThreads ?? 12
        semaphore = DispatchSemaphore(value: limit)
        queue = DispatchQueue(label: "custom-queue", qos: DispatchQoS.userInteractive, attributes: DispatchQueue.Attributes.concurrent)
    }
    
    if let queue = queue {
        let lock = NSLock()
        for filePath in files {
            _ = semaphore?.wait(timeout: DispatchTime.distantFuture)
            queue.async {
                block(filePath, lock)
                semaphore?.signal()
            }
        }
        // Wait for queue to drain
        queue.sync(flags: .barrier) {}
    } else {
        for filePath in files {
            block(filePath, nil)
        }
    }
}

func scanDirectory(_ path: String, with callBack: (String) -> Void) {
    let errorHandler = { (url: URL, error: Error) -> Bool in
        fatalError("Failed to traverse \(url) with error \(error).")
    }
    if let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path, isDirectory: true), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles], errorHandler: errorHandler) {
        while let nextObjc = enumerator.nextObject() {
            if let fileUrl = nextObjc as? URL {
                callBack(fileUrl.path)
            }
        }
    }
}

func scanPaths(_ paths: [String], with callBack: (String) -> Void) {
    for path in paths {
        scanDirectory(path, with: callBack)
    }
}
