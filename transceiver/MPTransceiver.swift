//
//  MPTransceiver.swift
//  MPTransceiver
//
//  p2p
//
//  Created by Jason Jobe on 6/7/18.
//  Copyright © 2018 Jason Jobe. All rights reserved.
//

import Foundation
import MultipeerConnectivity

public class MPTransceiver: NSObject {

    public static var shared: MPTransceiver {
        get {
            _shared = _shared ?? MPTransceiver(serviceType: "mpt_hub")
            return _shared!
        }
        set { _shared = newValue }
    }
    static var _shared: MPTransceiver?

    // MARK: Properties

    public weak var delegate: MPTransceiverDelegate?

    /** Name of session: Limited to one hyphen (-) and 15 characters */
    var serviceType: String

    var devicePeerID: MCPeerID

    /** Advertises session */
    var serviceAdvertiser: MCNearbyServiceAdvertiser
    var discoveryInfo: [String:String]? = nil

    var serviceBrowser: MCNearbyServiceBrowser

    public var connectionTimeout = 10.0
    public var peers: [MCPeerID: MPTPeer] = [:]

    /** Peers that are currently connected */
    public var connectedPeers: [MPTPeer] {
        return peers.values.filter({ $0.state == .connected })
    }

    /** Name of the peers that are currently connected */
    public var connectedDeviceNames: [String] {
        return session.connectedPeers.map({$0.displayName})
    }

    /// Prints out all errors and status updates
    public var debugMode = false

    /** Main session object that manages the current connections */
    lazy var session: MCSession = {
        let session = MCSession(peer: self.devicePeerID,
                                securityIdentity: nil, encryptionPreference: .optional)
        session.delegate = self
        return session
    }()

    // MARK: - Constructors

    /// Initializes the MPTransceiver service with a serviceType and a custom deviceName
    /// - Parameters:
    ///     - serviceType: String with name of the service. Up to one hyphen (-) and 15 characters.
    ///     - deviceName: String containing custom name for device, max length is 63 UTF-8

    public init(serviceType: String, displayName: String? = nil, info: [String:String]? = nil) {

        let name = displayName ?? (CommandLine.arguments[0] as NSString).lastPathComponent

        // Setup device/session properties
        self.serviceType = serviceType
        self.devicePeerID = MCPeerID(displayName: name)
        self.discoveryInfo = info

        // Setup the service advertiser
        self.serviceAdvertiser = MCNearbyServiceAdvertiser(peer: self.devicePeerID,
                                                           discoveryInfo: info,
                                                           serviceType: serviceType)
        // Setup the service browser
        self.serviceBrowser = MCNearbyServiceBrowser(peer: self.devicePeerID,
                                                     serviceType: serviceType)

        super.init()
        self.serviceAdvertiser.delegate = self
        self.serviceBrowser.delegate = self
    }

    // deinit: Its good to explictly stop advertising and browsing services
    // rather than have peers wait for a timeout
    deinit {
        disconnect()
    }

    // MARK: - Methods

    /// HOST: Automatically browses and invites all found devices
    public func startInviting() {
        self.serviceBrowser.startBrowsingForPeers()
    }

    /// MEMBER: Automatically advertises and accepts all invites
    public func startAccepting() {
        self.serviceAdvertiser.startAdvertisingPeer()
    }

    /// HOST and MEMBER: Uses both advertising and browsing to connect.
    public func autoConnect() {
        startInviting()
        startAccepting()
    }

    /// Stops the invitation process
    public func stopInviting() {
        self.serviceBrowser.stopBrowsingForPeers()
    }

    /// Stops accepting invites and becomes invisible on the network
    public func stopAccepting() {
        self.serviceAdvertiser.stopAdvertisingPeer()
    }

    /// Stops all invite/accept services
    public func stopSearching() {
        stopAccepting()
        stopInviting()
    }

    /// Disconnects from the current session and stops all searching activity
    public func disconnect() {
        session.disconnect()
        peers.removeAll()
    }

    /// Stops all invite/accept services, disconnects from the current session, and stops all searching activity
    public func end() {
        stopSearching()
        disconnect()
    }

    /// Returns true if there are any connected peers
    public var isConnected: Bool {
        return connectedPeers.count > 0
    }

    /// Sends a Codable object and type to all connected peers.
    /// - Parameters:
    ///     - object: Any to send to all connected peers.
    ///     - header: An optional dictionary for any packet metadata apart from the payload
    public func send(_ object: Any, to receiver: MPTPeer? = nil, header: [String:Any] = [:]) {
        if isConnected {
            do {
                let packet: [Any] = [object, header]
                let receivers = (receiver != nil) ? [receiver!.peerID] : session.connectedPeers
                let item = try NSKeyedArchiver.archivedData(withRootObject: packet,
                                                            requiringSecureCoding: false)
                try session.send(item, toPeers: receivers, with: MCSessionSendDataMode.reliable)
            } catch let error {
                printDebug(error.localizedDescription)
            }
        }
    }

    public func broadcastResource(at url: URL, withName name: String,
                             withCompletionHandler cb: ((Error?) -> Void)?) {
        for p in connectedPeers {
            sendResource(at: url, withName: name, toPeer: p, withCompletionHandler: cb)
        }
    }

    public func sendResource(at url: URL, withName name: String, toPeer peer: MPTPeer,
                             withCompletionHandler cb: ((Error?) -> Void)?) {
        if session.connectedPeers.contains(peer.peerID) {
            session.sendResource(at: url, withName: name, toPeer: peer.peerID,
                                 withCompletionHandler: cb)
        }
    }

    /** Prints only if in debug mode */
    fileprivate func printDebug(_ string: @autoclosure () -> String) {
        if debugMode {
            print(string())
        }
    }

}

// MARK: - Advertiser Delegate
extension MPTransceiver: MCNearbyServiceAdvertiserDelegate {

    /// Received invitation
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {

        OperationQueue.main.addOperation {
            invitationHandler(true, self.session)
        }
    }

    /// Error, could not start advertising
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        printDebug("Could not start advertising due to error: \(error)")
    }

}

// MARK: - Browser Delegate
extension MPTransceiver: MCNearbyServiceBrowserDelegate {

    /// Found a peer, update the list of peers
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                        withDiscoveryInfo info: [String: String]?)
    {
        printDebug("Found peer: \(peerID)")

        // Update the list of available peers
        peers[peerID] = MPTPeer(peerID: peerID, state: .notConnected, info: info)
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: connectionTimeout)
    }

    /// Lost a peer, update the state of our Peer
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        printDebug("Lost peer: \(peerID)")
        peers[peerID]?.state = .notConnected
    }

    /// Error, could not start browsing
    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        printDebug("Could not start browsing due to error: \(error)")
    }

}

// MARK: - Session Delegate
extension MPTransceiver: MCSessionDelegate {

    /// Peer changed state, update all connected peers and send new connection list to delegate connectedDevicesChanged
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        peers[peerID]?.state = state

        // Send new connection list to delegate
        OperationQueue.main.addOperation {
            self.delegate?.transceiver(self, connectedDevicesChanged: session.connectedPeers.map({$0.displayName}))
        }
    }

    /// Received data, update delegate didRecieveData
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        printDebug("Received data: \(data.count) bytes")
//        guard let packet = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [Any]
//            else { return }
        guard let packet = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as! [Any]
            else { return }
        guard let payload = packet.first else { return }
        guard let header = packet[1] as? [String:Any] else { return }

        let peer = peers[peerID]

        OperationQueue.main.addOperation {
            self.delegate?.transceiver(self, didReceive: payload, header: header, from: peer)
        }
    }

    /// Received stream
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        printDebug("Received stream")
    }

    /// Started receiving resource
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        printDebug("Started receiving resource with name: \(resourceName)")
    }

    /// Finished receiving resource
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        printDebug("Finished receiving resource with name: \(resourceName)")
    }

}

///////////////////////////////////
public protocol MPTransceiverDelegate: class {

    /// didReceiveData: delegate runs on receiving data from another peer
    func transceiver(_  hub: MPTransceiver, didReceive: Any, header: [String:Any], from: MPTPeer?)

    /// connectedDevicesChanged: delegate runs on connection/disconnection event in session
    func transceiver(_ hub: MPTransceiver, connectedDevicesChanged: [String])

}

/////////////////////////////////////////

/// Class containing peerID and session state
public class MPTPeer {

    var peerID: MCPeerID
    var state: MCSessionState
    var info: [String: String]?

    init(peerID: MCPeerID, state: MCSessionState, info: [String: String]?) {
        self.peerID = peerID
        self.state = state
        self.info = info
    }
}

