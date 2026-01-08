//
//  ESMachListener.swift
//  ESExtension
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation
import os

extension ESManager: NSXPCListenerDelegate {

    func setupMachListener() {
        xpcLock.perform {
            if listener != nil {
                return
            }

            let listen = NSXPCListener(
                machServiceName: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc"
            )
            listen.delegate = self
            listen.resume()
            listener = listen
            Logfile.es.log(
                """
                MachService XPC listener resumed: \
                endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc
                """
            )
        }
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {

        Logfile.es.log(
            """
            Incoming XPC connection attempt \
            (pid=\(newConnection.processIdentifier, privacy: .public))
            """
        )

        newConnection.exportedInterface =
            NSXPCInterface(with: ESAppProtocol.self)
        newConnection.exportedObject = self

        newConnection.remoteObjectInterface =
            NSXPCInterface(with: ESXPCProtocol.self)

        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let self, let conn = newConnection else { return }
            Logfile.es.log("Incoming XPC connection invalidated")
            self.removeIncomingConnection(conn)
        }

        newConnection.interruptionHandler = {
            Logfile.es.log("Incoming XPC connection interrupted")
        }

        storeIncomingConnection(newConnection)
        newConnection.resume()

        Logfile.es.log("Accepted new XPC connection from client")
        return true
    }
}
