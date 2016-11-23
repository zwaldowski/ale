//
//  Process.swift
//  Command
//
//  Created by Zachary Waldowski on 11/22/16.
//  Copyright © 2015 Carthage. All rights reserved.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

import Foundation

extension Process {

    static func waitToExecute(atPath path: String, arguments: [String]) -> Int32 {
        let task = Process()
        task.launchPath = path
        task.arguments = arguments

        task.launch()
        task.waitUntilExit()

        return task.terminationStatus
    }
    
}
