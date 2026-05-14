//
//  FirmwareUpdateBLECommands.swift
//  FlySightCore
//
//  Created by Codex on 2026-05-14.
//

import Foundation

public extension FlySightCore {
    enum FirmwareUpdateBLEPath {
        public static let flysightStateFile = "FLYSIGHT.TXT"
        public static let firmwareDirectory = "FW"
        public static let applicationImage = "FW/APP.SFB"
        public static let stackImage = "FW/STACK.BIN"
    }

    enum FirmwareUpdateBLECommands {
        public static func readStateFile() -> Data {
            readFile(path: FirmwareUpdateBLEPath.flysightStateFile)
        }

        public static func createFirmwareDirectory() -> Data {
            nullTerminatedCommand(
                opcode: FTControlOpcodes.createDirectory,
                path: FirmwareUpdateBLEPath.firmwareDirectory
            )
        }

        public static func openApplicationImageForWrite() -> Data {
            writeFileOpen(path: FirmwareUpdateBLEPath.applicationImage)
        }

        public static func openStackImageForWrite() -> Data {
            writeFileOpen(path: FirmwareUpdateBLEPath.stackImage)
        }

        public static func installUploadedFirmware() -> Data {
            Data([DSControlOpcodes.installUploadedFirmware])
        }

        static func readFile(
            path: String,
            offsetMultiplier: UInt32 = 0,
            strideMinusOneMultiplier: UInt32 = 0
        ) -> Data {
            var command = Data([FTControlOpcodes.readFile])
            command.append(offsetMultiplier.littleEndianData)
            command.append(strideMinusOneMultiplier.littleEndianData)
            command.append(path.data(using: .utf8) ?? Data())
            command.append(0x00)
            return command
        }

        static func writeFileOpen(path: String) -> Data {
            nullTerminatedCommand(opcode: FTControlOpcodes.writeFileOpen, path: path)
        }

        private static func nullTerminatedCommand(opcode: UInt8, path: String) -> Data {
            var command = Data([opcode])
            command.append(path.data(using: .utf8) ?? Data())
            command.append(0x00)
            return command
        }
    }

    enum FirmwareUpdateBLEError: LocalizedError, Equatable {
        case invalidStateFileEncoding
        case fileTransferOperationInProgress
        case controlPointResponseTooShort
        case fileTransferResponseTooShort
        case unexpectedFileTransferResponse(responseOpcode: UInt8)
        case unexpectedFileTransferOpcode(expected: UInt8, actual: UInt8)
        case unexpectedControlPointResponse(responseID: UInt8)
        case unexpectedControlPointOpcode(expected: UInt8, actual: UInt8)
        case fileTransferCommandRejected(opcode: UInt8)
        case controlPointRejected(status: UInt8)

        public var errorDescription: String? {
            switch self {
            case .invalidStateFileEncoding:
                return "FLYSIGHT.TXT was not valid UTF-8."
            case .fileTransferOperationInProgress:
                return "A file transfer operation is already in progress."
            case .controlPointResponseTooShort:
                return "The device state control point response was too short."
            case .fileTransferResponseTooShort:
                return "The file transfer response was too short."
            case .unexpectedFileTransferResponse(let responseOpcode):
                return "Unexpected file transfer response 0x\(String(format: "%02X", responseOpcode))."
            case .unexpectedFileTransferOpcode(let expected, let actual):
                return "Expected response for file transfer command 0x\(String(format: "%02X", expected)), got 0x\(String(format: "%02X", actual))."
            case .unexpectedControlPointResponse(let responseID):
                return "Unexpected control point response 0x\(String(format: "%02X", responseID))."
            case .unexpectedControlPointOpcode(let expected, let actual):
                return "Expected response for device state command 0x\(String(format: "%02X", expected)), got 0x\(String(format: "%02X", actual))."
            case .fileTransferCommandRejected(let opcode):
                return "File transfer command 0x\(String(format: "%02X", opcode)) was rejected."
            case .controlPointRejected(let status):
                return "Device state command was rejected with status 0x\(String(format: "%02X", status))."
            }
        }
    }
}
