import Foundation
@testable import FlySightFirmware
import XCTest

final class FirmwareUpdateCoordinatorTests: XCTestCase {
    func testPerformUpdateHappyPathUsesRecommendedFirmware() async throws {
        let recommended = Self.option(version: "v2024.12.30.8", stackRequired: false)
        let manifest = Self.manifest(recommended: recommended, firmwares: [recommended])
        let client = FakeFirmwareClient(manifest: manifest, downloads: [
            recommended.firmware.url: .success(Self.appData)
        ])
        let ble = FakeFirmwareUpdateBLETransport()
        var states: [FirmwareUpdateState] = []
        let coordinator = FirmwareUpdateCoordinator(client: client, bleTransport: ble) { states.append($0) }

        let result = try await coordinator.performUpdate()

        XCTAssertEqual(result, FirmwareUpdateResult(
            firmwareVersion: recommended.version,
            firmwareTargetPath: "FW/APP.SFB",
            stackRequiredVersion: nil,
            stackTargetPath: nil,
            stackUploaded: false
        ))
        XCTAssertEqual(client.fetchRequests, [
            .init(flysightText: Self.flysightText, includeBeta: false)
        ])
        XCTAssertEqual(client.downloadsRequested, [recommended.firmware])
        XCTAssertEqual(ble.calls, [
            .readStateFile,
            .ensureFirmwareDirectory,
            .upload(targetPath: "FW/APP.SFB", data: Self.appData),
            .installUploadedFirmware
        ])
        XCTAssertEqual(states, [
            .readingStateFile,
            .fetchingManifest(includeBeta: false),
            .ready(manifest: manifest, selectedFirmware: recommended),
            .downloadingFirmware(recommended.firmware),
            .creatingFirmwareDirectory,
            .uploadingFirmware(recommended.firmware),
            .requestingInstall,
            .completed(result)
        ])
    }

    func testStackRequiredPathDownloadsAndUploadsStackBeforeFirmware() async throws {
        let option = Self.option(version: "v2024.12.30.8", stackRequired: true)
        let manifest = Self.manifest(recommended: option, firmwares: [option])
        let client = FakeFirmwareClient(manifest: manifest, downloads: [
            option.stack.file!.url: .success(Self.stackData),
            option.firmware.url: .success(Self.appData)
        ])
        let ble = FakeFirmwareUpdateBLETransport()
        let coordinator = FirmwareUpdateCoordinator(client: client, bleTransport: ble)

        let result = try await coordinator.performUpdate()

        XCTAssertTrue(result.stackUploaded)
        XCTAssertEqual(result.stackRequiredVersion, "1.19.0")
        XCTAssertEqual(result.stackTargetPath, "FW/STACK.BIN")
        XCTAssertEqual(client.downloadsRequested, [
            option.stack.file!,
            option.firmware
        ])
        XCTAssertEqual(ble.calls, [
            .readStateFile,
            .ensureFirmwareDirectory,
            .upload(targetPath: "FW/STACK.BIN", data: Self.stackData),
            .upload(targetPath: "FW/APP.SFB", data: Self.appData),
            .installUploadedFirmware
        ])
    }

    func testNoStackPathSkipsStackDownloadAndUpload() async throws {
        let option = Self.option(version: "v2024.12.30.8", stackRequired: false)
        let manifest = Self.manifest(recommended: option, firmwares: [option])
        let client = FakeFirmwareClient(manifest: manifest, downloads: [
            option.firmware.url: .success(Self.appData)
        ])
        let ble = FakeFirmwareUpdateBLETransport()
        let coordinator = FirmwareUpdateCoordinator(client: client, bleTransport: ble)

        _ = try await coordinator.performUpdate()

        XCTAssertEqual(client.downloadsRequested, [option.firmware])
        XCTAssertFalse(ble.calls.contains { call in
            if case .upload(let targetPath, _) = call {
                return targetPath == "FW/STACK.BIN"
            }
            return false
        })
    }

    func testSelectedVersionUsesChosenFirmware() async throws {
        let recommended = Self.option(version: "v2024.12.30.8", appFileName: "recommended.sfb", stackRequired: false)
        let selected = Self.option(version: "v2026.03.06.develop", appFileName: "selected.sfb", stackRequired: false)
        let manifest = Self.manifest(recommended: recommended, firmwares: [recommended, selected])
        let client = FakeFirmwareClient(manifest: manifest, downloads: [
            selected.firmware.url: .success(Self.selectedAppData)
        ])
        let ble = FakeFirmwareUpdateBLETransport()
        var states: [FirmwareUpdateState] = []
        let coordinator = FirmwareUpdateCoordinator(client: client, bleTransport: ble) { states.append($0) }

        let result = try await coordinator.performUpdate(selectedVersion: selected.version)

        XCTAssertEqual(result.firmwareVersion, selected.version)
        XCTAssertEqual(client.downloadsRequested, [selected.firmware])
        XCTAssertTrue(states.contains(.ready(manifest: manifest, selectedFirmware: selected)))
        XCTAssertFalse(states.contains(.downloadingFirmware(recommended.firmware)))
    }

    func testEndpointErrorStopsAfterReadAndFetch() async throws {
        let option = Self.option(version: "v2024.12.30.8", stackRequired: false)
        let endpointError = FirmwareUpdateClientError.endpoint(
            FirmwareEndpointError(code: "config_txt", message: "This looks like CONFIG.TXT.", status: 400),
            statusCode: 400
        )
        let client = FakeFirmwareClient(
            manifest: Self.manifest(recommended: option, firmwares: [option]),
            fetchError: endpointError
        )
        let ble = FakeFirmwareUpdateBLETransport()
        let coordinator = FirmwareUpdateCoordinator(client: client, bleTransport: ble)

        do {
            _ = try await coordinator.performUpdate()
            XCTFail("Expected endpoint error")
        } catch FirmwareUpdateClientError.endpoint(let error, let statusCode) {
            XCTAssertEqual(error.knownCode, .configTxt)
            XCTAssertEqual(statusCode, 400)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(ble.calls, [.readStateFile])
        XCTAssertEqual(client.downloadsRequested, [])
        assertFailed(coordinator.state)
    }

    func testDownloadFailureStopsBeforeBLEWrites() async throws {
        let option = Self.option(version: "v2024.12.30.8", stackRequired: false)
        let downloadError = FirmwareUpdateClientError.downloadSHA256Mismatch(
            expected: String(repeating: "0", count: 64),
            actual: String(repeating: "1", count: 64)
        )
        let client = FakeFirmwareClient(manifest: Self.manifest(recommended: option, firmwares: [option]), downloads: [
            option.firmware.url: .failure(downloadError)
        ])
        let ble = FakeFirmwareUpdateBLETransport()
        let coordinator = FirmwareUpdateCoordinator(client: client, bleTransport: ble)

        do {
            _ = try await coordinator.performUpdate()
            XCTFail("Expected download error")
        } catch FirmwareUpdateClientError.downloadSHA256Mismatch(let expected, let actual) {
            XCTAssertEqual(expected, String(repeating: "0", count: 64))
            XCTAssertEqual(actual, String(repeating: "1", count: 64))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(ble.calls, [.readStateFile])
        assertFailed(coordinator.state)
    }

    func testUploadFailureStopsBeforeInstall() async throws {
        let option = Self.option(version: "v2024.12.30.8", stackRequired: false)
        let client = FakeFirmwareClient(manifest: Self.manifest(recommended: option, firmwares: [option]), downloads: [
            option.firmware.url: .success(Self.appData)
        ])
        let ble = FakeFirmwareUpdateBLETransport()
        ble.uploadError = TestError.uploadFailed
        let coordinator = FirmwareUpdateCoordinator(client: client, bleTransport: ble)

        do {
            _ = try await coordinator.performUpdate()
            XCTFail("Expected upload error")
        } catch TestError.uploadFailed {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(ble.calls, [
            .readStateFile,
            .ensureFirmwareDirectory,
            .upload(targetPath: "FW/APP.SFB", data: Self.appData)
        ])
        assertFailed(coordinator.state)
    }

    func testInstallFailureSurfacesAfterUpload() async throws {
        let option = Self.option(version: "v2024.12.30.8", stackRequired: false)
        let client = FakeFirmwareClient(manifest: Self.manifest(recommended: option, firmwares: [option]), downloads: [
            option.firmware.url: .success(Self.appData)
        ])
        let ble = FakeFirmwareUpdateBLETransport()
        ble.installError = TestError.installFailed
        let coordinator = FirmwareUpdateCoordinator(client: client, bleTransport: ble)

        do {
            _ = try await coordinator.performUpdate()
            XCTFail("Expected install error")
        } catch TestError.installFailed {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(ble.calls, [
            .readStateFile,
            .ensureFirmwareDirectory,
            .upload(targetPath: "FW/APP.SFB", data: Self.appData),
            .installUploadedFirmware
        ])
        assertFailed(coordinator.state)
    }

    fileprivate static let flysightText = "Firmware_Ver: v2024.12.30.8;\nDevice_ID: 1234;"
    private static let appData = Data("app".utf8)
    private static let selectedAppData = Data("selected-app".utf8)
    private static let stackData = Data("stack".utf8)

    private static func manifest(recommended: FirmwareOption, firmwares: [FirmwareOption]) -> FirmwareManifest {
        FirmwareManifest(
            device: FirmwareDevice(
                firmwareVersion: "v2024.12.30.8",
                stackVersion: "1.18.0",
                stackVersionUnknown: false,
                pubkeyX: String(repeating: "a", count: 64),
                legacy: false
            ),
            includeBeta: false,
            recommended: recommended,
            firmwares: firmwares
        )
    }

    private static func option(
        version: String,
        appFileName: String = "app.sfb",
        stackRequired: Bool
    ) -> FirmwareOption {
        let stackFile = FirmwareFile(
            url: URL(string: "https://example.com/\(version)/stack.bin")!,
            targetPath: "FW/STACK.BIN",
            sizeBytes: stackData.count,
            sha256: String(repeating: "1", count: 64)
        )

        return FirmwareOption(
            version: version,
            releaseDate: "2026-03-06",
            isBeta: false,
            releaseNotesURL: nil,
            firmware: FirmwareFile(
                url: URL(string: "https://example.com/\(version)/\(appFileName)")!,
                targetPath: "FW/APP.SFB",
                sizeBytes: appData.count,
                sha256: String(repeating: "0", count: 64)
            ),
            stack: StackUpdate(
                requiredVersion: "1.19.0",
                currentVersion: "1.18.0",
                currentVersionUnknown: false,
                updateRequired: stackRequired,
                file: stackRequired ? stackFile : nil
            )
        )
    }

    private func assertFailed(_ state: FirmwareUpdateState, file: StaticString = #filePath, line: UInt = #line) {
        guard case .failed = state else {
            XCTFail("Expected failed state, got \(state)", file: file, line: line)
            return
        }
    }
}

private struct FetchRequest: Equatable {
    let flysightText: String
    let includeBeta: Bool
}

private final class FakeFirmwareClient: FirmwareUpdateClientProtocol {
    private let manifest: FirmwareManifest
    private let fetchError: Error?
    private let downloads: [URL: Result<Data, Error>]

    private(set) var fetchRequests: [FetchRequest] = []
    private(set) var downloadsRequested: [FirmwareFile] = []

    init(
        manifest: FirmwareManifest,
        fetchError: Error? = nil,
        downloads: [URL: Result<Data, Error>] = [:]
    ) {
        self.manifest = manifest
        self.fetchError = fetchError
        self.downloads = downloads
    }

    func fetchFirmwareOptions(flysightText: String, includeBeta: Bool) async throws -> FirmwareManifest {
        fetchRequests.append(.init(flysightText: flysightText, includeBeta: includeBeta))
        if let fetchError = fetchError {
            throw fetchError
        }
        return manifest
    }

    func downloadAndVerify(_ file: FirmwareFile) async throws -> Data {
        downloadsRequested.append(file)
        guard let result = downloads[file.url] else {
            throw TestError.missingDownload
        }
        return try result.get()
    }
}

private final class FakeFirmwareUpdateBLETransport: FirmwareUpdateBLETransport {
    enum Call: Equatable {
        case readStateFile
        case ensureFirmwareDirectory
        case upload(targetPath: String, data: Data)
        case installUploadedFirmware
    }

    var flysightText = FirmwareUpdateCoordinatorTests.flysightText
    var readError: Error?
    var ensureDirectoryError: Error?
    var uploadError: Error?
    var installError: Error?

    private(set) var calls: [Call] = []

    func readFlysightStateFile() async throws -> String {
        calls.append(.readStateFile)
        if let readError = readError {
            throw readError
        }
        return flysightText
    }

    func ensureFirmwareUpdateDirectory() async throws {
        calls.append(.ensureFirmwareDirectory)
        if let ensureDirectoryError = ensureDirectoryError {
            throw ensureDirectoryError
        }
    }

    func uploadFirmwareUpdateFile(_ data: Data, targetPath: String) async throws {
        calls.append(.upload(targetPath: targetPath, data: data))
        if let uploadError = uploadError {
            throw uploadError
        }
    }

    func installUploadedFirmware() async throws {
        calls.append(.installUploadedFirmware)
        if let installError = installError {
            throw installError
        }
    }
}

private enum TestError: Error, Equatable {
    case missingDownload
    case uploadFailed
    case installFailed
}
