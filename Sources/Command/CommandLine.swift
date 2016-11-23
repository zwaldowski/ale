//
//  CommandLine.swift
//  Command
//
//  Created by Zachary Waldowski on 11/21/16.
//  Copyright © 2015 Carthage. All rights reserved.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

import Foundation

extension CommandLine {

    static var executableName: String {
        return URL(fileURLWithPath: arguments[0]).lastPathComponent
    }

    struct Stream: TextOutputStream {
        private let fd: UnsafeMutablePointer<FILE>
        fileprivate init(fd: UnsafeMutablePointer<FILE>) {
            self.fd = fd
        }

        public func write(_ string: String) {
            flockfile(fd)
            for c in string.utf8 {
                putc_unlocked(numericCast(c), fd)
            }
            funlockfile(fd)
        }
    }

    @_transparent
    static var standardError: Stream {
        get {
            return Stream(fd: Darwin.stderr)
        }
        set { }
    }

}
