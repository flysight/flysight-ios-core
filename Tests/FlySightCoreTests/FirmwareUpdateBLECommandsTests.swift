import XCTest
@testable import FlySightCore

final class FirmwareUpdateBLECommandsTests: XCTestCase {
    func testFirmwareUpdatePathsMatchBootloaderTargets() {
        XCTAssertEqual(FlySightCore.FirmwareUpdateBLEPath.flysightStateFile, "FLYSIGHT.TXT")
        XCTAssertEqual(FlySightCore.FirmwareUpdateBLEPath.firmwareDirectory, "FW")
        XCTAssertEqual(FlySightCore.FirmwareUpdateBLEPath.applicationImage, "FW/APP.SFB")
        XCTAssertEqual(FlySightCore.FirmwareUpdateBLEPath.stackImage, "FW/STACK.BIN")
    }

    func testReadStateFileCommand() {
        var expected = Data([FlySightCore.FTControlOpcodes.readFile])
        expected.append(UInt32(0).littleEndianData)
        expected.append(UInt32(0).littleEndianData)
        expected.append(Data("FLYSIGHT.TXT".utf8))
        expected.append(0x00)

        XCTAssertEqual(FlySightCore.FirmwareUpdateBLECommands.readStateFile(), expected)
    }

    func testCreateFirmwareDirectoryCommand() {
        XCTAssertEqual(
            FlySightCore.FirmwareUpdateBLECommands.createFirmwareDirectory(),
            Data([FlySightCore.FTControlOpcodes.createDirectory]) + Data("FW".utf8) + Data([0x00])
        )
    }

    func testOpenApplicationImageForWriteCommand() {
        XCTAssertEqual(
            FlySightCore.FirmwareUpdateBLECommands.openApplicationImageForWrite(),
            Data([FlySightCore.FTControlOpcodes.writeFileOpen]) + Data("FW/APP.SFB".utf8) + Data([0x00])
        )
    }

    func testOpenStackImageForWriteCommand() {
        XCTAssertEqual(
            FlySightCore.FirmwareUpdateBLECommands.openStackImageForWrite(),
            Data([FlySightCore.FTControlOpcodes.writeFileOpen]) + Data("FW/STACK.BIN".utf8) + Data([0x00])
        )
    }

    func testInstallUploadedFirmwareCommand() {
        XCTAssertEqual(FlySightCore.DSControlOpcodes.installUploadedFirmware, 0x04)
        XCTAssertEqual(
            FlySightCore.FirmwareUpdateBLECommands.installUploadedFirmware(),
            Data([0x04])
        )
    }

    func testRequestSleepModeCommand() {
        XCTAssertEqual(FlySightCore.DSControlOpcodes.requestSleep, 0x10)
        XCTAssertEqual(
            FlySightCore.FirmwareUpdateBLECommands.requestSleepMode(),
            Data([0x10])
        )
    }
}
