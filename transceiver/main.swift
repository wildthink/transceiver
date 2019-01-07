#!/usr/bin/swift
//#!/usr/bin/swift -F myFramework_path
//  main.swift
//  transceiver
//
//  Created by Jason Jobe on 6/7/18.
//  Copyright © 2018 Jason Jobe. All rights reserved.
//

import Foundation

extension MCConsole: MPTransceiverDelegate {
    func transceiver(_ hub: MPTransceiver, didReceive payload: Any, header:[String:Any], from sender: MPTPeer?) {
        guard var message = payload as? String else { return }

        if let p = sender {
            message = "(\(p.peerID.displayName)): \(message)"
        }
        write (message)
    }

    func transceiver(_ hub: MPTransceiver, connectedDevicesChanged devices: [String]) {
        write("Connected devices changed: \(devices)")
    }
}

class MCConsole: Console {
    var hub: MPTransceiver

    init (_ name: String, service: String) {
        self.hub = MPTransceiver(serviceType: service, displayName: name, info: nil)
        super.init()
        self.hub.delegate = self

        hub.autoConnect()
    }

    override func quit() {
        hub.disconnect()
        super.quit()
    }
    override func process(_ input: String) {
        let words = input.components(separatedBy: " ")
        let cmd = words[0]

        switch cmd {
        case "/start":
            hub.autoConnect()
            write ("(me): started")
        case "/stop":
            hub.end()
            //            hub.disconnect()
            write ("(me): disconnected")
        case "/who":
            write ("(who): ", eom: false)
            let peers = hub.connectedDeviceNames
            write (peers.description)
        case "/whoami":
            write ("(\(cmd)): ", eom: false)
            let me = hub.devicePeerID.description
            write (me)
        case "help":
            printUsage()
        case "/echo":
            write ("(echo): ", eom: false)
            write (input)
        default:
            if cmd.hasPrefix("/") {
                write("Unexpected command '\(cmd)'")
                return
            }
            write ("(say): ", eom: false)
            write (input)
            hub.send(input)
        }
    }

}

let name: String = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : (CommandLine.arguments[0] as NSString).lastPathComponent


let console = MCConsole(name, service: "p2p")
console.start()

RunLoop.current.run()

