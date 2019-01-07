//
//  Console.swift
//  transceiver
//
//  Created by Jason Jobe on 6/7/18.
//  Copyright © 2018 Jason Jobe. All rights reserved.
//
import Foundation
class Console {

    enum OutputType {
        case error
        case standard
    }

    var prompt: String = "> "
    var echo_input: Bool = false
    var quit_cmds = ["/exit", "/quit", "/bye", "/q"]

    func write(_ message: String, to: OutputType = .standard, eom: Bool = true) {
        switch to {
        case .standard:
            if let data = (message).data(using: .utf8) {
                FileHandle.standardOutput.write(data)
            }
            if eom {
                if let data = "\n\(prompt)".data(using: .utf8) {
                    FileHandle.standardOutput.write(data)
                }
            }
        case .error:
            fputs("\u{001B}[0;31m\(message)\n", stderr)
        }
    }

    func printUsage() {
        let executableName = (CommandLine.arguments[0] as NSString).lastPathComponent
        write("usage:")
        write("\(executableName)")
    }

    func read() -> String? {
        let inputData = FileHandle.standardInput.availableData
        var str = String(data: inputData, encoding: String.Encoding.utf8)!
        str = str.trimmingCharacters(in: CharacterSet.newlines)
        return str.isEmpty ? nil : str
    }

    @objc func inputAvailable(_ notice: Notification) {
        defer {
            FileHandle.standardInput.waitForDataInBackgroundAndNotify()
        }
        guard FileHandle.standardInput == notice.object as? FileHandle else { return }
        if let str = read() {
            if quit_cmds.contains(str) { quit() }
            if echo_input { write (str) }
            process(str)
        }
    }

    func start() {
        write (prompt, eom: false)
        NotificationCenter.default.addObserver(self, selector: #selector(inputAvailable(_:)), name: .NSFileHandleDataAvailable, object: nil)
        FileHandle.standardInput.waitForDataInBackgroundAndNotify()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
    }

    func process(_ input: String) {
        write ("(echo): ", eom: false)
        write (input)
    }

    func quit() {
        exit(0)
    }
}
