// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import StikJIT

@objc(RALabJITHelper)
final class RALabJITHelper: NSObject, NSExtensionRequestHandling {
    private static let queue = DispatchQueue(label: "retroarch.lab.jit.helper")

    func beginRequest(with context: NSExtensionContext) {
        let request = (context.inputItems.first as? NSExtensionItem)?.userInfo ?? [:]
        Self.queue.async {
            let response: [String: Any]
            do {
                response = try Self.handle(request)
            } catch {
                response = ["success": false, "message": error.localizedDescription]
            }
            let item = NSExtensionItem()
            item.userInfo = response
            context.completeRequest(returningItems: [item], completionHandler: nil)
        }
    }

    private static func handle(_ request: [AnyHashable: Any]) throws -> [String: Any] {
        let files = FileManager.default
        var root = files.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StikJIT", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        try root.setResourceValues(excluded)
        let paths = DDIPaths.default(in: root)
        guard let operation = request["operation"] as? String,
              ["reset", "prepare", "enable"].contains(operation) else {
            throw failure("Invalid JIT operation.")
        }
        if operation == "reset" {
            try StikJIT.resetCachedDDI(at: paths)
            return ["success": true, "message": "Developer Disk Image cache reset."]
        }
        guard let pairing = request["pairing"] as? Data, !pairing.isEmpty,
              pairing.count <= 1024 * 1024 else {
            throw failure("No usable device pairing file was supplied.")
        }
        // The directory is private and excluded from backups; remove interrupted copies too.
        for file in try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            where file.lastPathComponent.hasPrefix("pairing-") {
            try files.removeItem(at: file)
        }
        let temporary = root.appendingPathComponent("pairing-\(UUID().uuidString).plist")
        try pairing.write(to: temporary, options: [.atomic, .completeFileProtection])
        defer { try? files.removeItem(at: temporary) }
        if operation == "prepare" {
            switch StikJIT.prepareDevice(pairingFile: temporary, paths: paths) {
            case .ready(let state):
                let txm = state.isTXMPresent.map { $0 ? "Present" : "Not present" } ?? "Unknown"
                return ["success": true, "message": "Device ready. TXM: \(txm)."]
            case .unreachable(let reason), .preparationFailed(let reason):
                return ["success": false, "message": reason]
            @unknown default:
                throw failure("Unknown preparation result.")
            }
        }
        guard let pid = request["pid"] as? NSNumber, pid.int32Value > 0 else {
            throw failure("Missing target process.")
        }
        try StikJIT.enableJIT(targetPID: pid.int32Value, pairingFile: temporary,
                             ddiPaths: paths, script: .universal, forceScript: true)
        return ["success": true, "message": "JIT is ready."]
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "RetroArchLabJIT", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
