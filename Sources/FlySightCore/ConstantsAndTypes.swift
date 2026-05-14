//
//  ConstantsAndTypes.swift
//  FlySightCore
//
//  Created by Michael Cooper on 2025-05-17.
//

import Foundation

public extension FlySightCore { // Also extends the FlySightCore enum namespace

    // General Control Point Protocol Constants
    public static let CP_RESPONSE_ID: UInt8        = 0xF0

    public struct CP_STATUS {
        public static let success: UInt8            = 0x01 // CP_STATUS_SUCCESS
        public static let cmdNotSupported: UInt8    = 0x02 // CP_STATUS_CMD_NOT_SUPPORTED
        public static let invalidParameter: UInt8   = 0x03 // CP_STATUS_INVALID_PARAMETER
        public static let operationFailed: UInt8    = 0x04 // CP_STATUS_OPERATION_FAILED
        public static let operationNotPermitted: UInt8 = 0x05 // CP_STATUS_OPERATION_NOT_PERMITTED
        public static let busy: UInt8               = 0x06 // CP_STATUS_BUSY

        // Moved cpStatusToString here as a static internal method
        static internal func string(for status: UInt8) -> String {
            switch status {
            case FlySightCore.CP_STATUS.success: return "Success"
            case FlySightCore.CP_STATUS.cmdNotSupported: return "Command Not Supported"
            case FlySightCore.CP_STATUS.invalidParameter: return "Invalid Parameter"
            case FlySightCore.CP_STATUS.operationFailed: return "Operation Failed"
            case FlySightCore.CP_STATUS.operationNotPermitted: return "Operation Not Permitted"
            case FlySightCore.CP_STATUS.busy: return "Busy"
            default: return "Unknown Status (0x\(String(format: "%02X", status)))"
            }
        }
    }

    // Constants for File Transfer (FT) command opcodes
    struct FTControlOpcodes {
        public static let delete: UInt8            = 0x01
        public static let readFile: UInt8          = 0x02
        public static let writeFileOpen: UInt8     = 0x03
        public static let createDirectory: UInt8   = 0x04
        public static let listDirectory: UInt8     = 0x05
        public static let fileData: UInt8          = 0x10
        public static let fileInfo: UInt8          = 0x11
        public static let ackFileData: UInt8       = 0x12
        public static let ping: UInt8              = 0xFE
        public static let cancelTransfer: UInt8    = 0xFF
    }

    // Constants for File Transfer (FT) ACK/NAK responses
    struct FTResponseOpcodes {
        public static let nak: UInt8               = 0xF0
        public static let ack: UInt8               = 0xF1
    }

    // Constants for Sensor Data (SD) Control Point Opcodes
    struct SDControlOpcodes { // Renamed from GNSSControlOpcodes
        public static let setMask: UInt8            = 0x01 // SD_CMD_SET_GNSS_BLE_MASK
        public static let getMask: UInt8            = 0x02 // SD_CMD_GET_GNSS_BLE_MASK
    }

    // Constants for Starter Pistol (SP) Control Point Opcodes
    struct SPControlOpcodes {
        public static let startCountdown: UInt8     = 0x01 // SP_CMD_START_COUNTDOWN
        public static let cancelCountdown: UInt8    = 0x02 // SP_CMD_CANCEL_COUNTDOWN
    }

    // Constants for Device State (DS) Control Point Opcodes
    struct DSControlOpcodes {
        public static let installUploadedFirmware: UInt8 = 0x04 // DS_CMD_INSTALL_UPLOADED_FIRMWARE
        public static let requestSleep: UInt8 = 0x10 // DS_CMD_REQUEST_SLEEP
    }

    public enum DeviceMode: Equatable {
        case sleep
        case active
        case config
        case usb
        case pairing
        case start
        case unknown(UInt8)

        public init(rawValue: UInt8) {
            switch rawValue {
            case 0x00:
                self = .sleep
            case 0x01:
                self = .active
            case 0x02:
                self = .config
            case 0x03:
                self = .usb
            case 0x04:
                self = .pairing
            case 0x05:
                self = .start
            default:
                self = .unknown(rawValue)
            }
        }

        public var rawValue: UInt8 {
            switch self {
            case .sleep:
                return 0x00
            case .active:
                return 0x01
            case .config:
                return 0x02
            case .usb:
                return 0x03
            case .pairing:
                return 0x04
            case .start:
                return 0x05
            case .unknown(let rawValue):
                return rawValue
            }
        }

        public var displayName: String {
            switch self {
            case .sleep:
                return "Idle"
            case .active:
                return "Active"
            case .config:
                return "Config"
            case .usb:
                return "USB"
            case .pairing:
                return "Pairing"
            case .start:
                return "Start"
            case .unknown(let rawValue):
                return "Unknown (0x\(String(format: "%02X", rawValue)))"
            }
        }

        public var requiresIdleBeforeFirmwareUpdate: Bool {
            self != .sleep
        }
    }
}
