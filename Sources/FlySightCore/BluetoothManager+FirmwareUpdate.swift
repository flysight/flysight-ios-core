//
//  BluetoothManager+FirmwareUpdate.swift
//  FlySightCore
//
//  Created by Codex on 2026-05-14.
//

import Foundation
import FlySightFirmware

extension FlySightCore.BluetoothManager: FirmwareUpdateBLETransport {
    public func uploadFirmwareUpdateFile(_ data: Data, targetPath: String) async throws {
        try await uploadFile(fileData: data, remotePath: targetPath)
    }

    public func readFirmwareUpdateFile(targetPath: String, knownSize: Int) async throws -> Data {
        try await downloadFile(at: targetPath, knownSize: UInt32(knownSize))
    }
}
