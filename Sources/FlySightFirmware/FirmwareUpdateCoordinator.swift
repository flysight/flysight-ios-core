import Foundation

public protocol FirmwareUpdateClientProtocol {
    func fetchFirmwareOptions(flysightText: String, includeBeta: Bool) async throws -> FirmwareManifest
    func downloadAndVerify(_ file: FirmwareFile) async throws -> Data
}

extension FirmwareUpdateClient: FirmwareUpdateClientProtocol {}

public protocol FirmwareUpdateBLETransport {
    func readFlysightStateFile() async throws -> String
    func ensureFirmwareUpdateDirectory() async throws
    func uploadFirmwareUpdateFile(_ data: Data, targetPath: String) async throws
    func readFirmwareUpdateFile(targetPath: String, knownSize: Int) async throws -> Data
    func installUploadedFirmware() async throws
}

public struct FirmwareUpdateResult: Equatable {
    public let firmwareVersion: String
    public let firmwareTargetPath: String
    public let stackRequiredVersion: String?
    public let stackTargetPath: String?
    public let stackUploaded: Bool

    public init(
        firmwareVersion: String,
        firmwareTargetPath: String,
        stackRequiredVersion: String?,
        stackTargetPath: String?,
        stackUploaded: Bool
    ) {
        self.firmwareVersion = firmwareVersion
        self.firmwareTargetPath = firmwareTargetPath
        self.stackRequiredVersion = stackRequiredVersion
        self.stackTargetPath = stackTargetPath
        self.stackUploaded = stackUploaded
    }
}

public enum FirmwareUpdateCoordinatorError: Error, Equatable {
    case noManifestLoaded
    case firmwareOptionUnavailable(version: String)
    case stackUpdateRequiredButMissingFile(version: String)
    case uploadedFileSizeMismatch(targetPath: String, expected: Int, actual: Int)
    case uploadedFileSHA256Mismatch(targetPath: String, expected: String, actual: String)
}

extension FirmwareUpdateCoordinatorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noManifestLoaded:
            return "No firmware manifest has been loaded."
        case .firmwareOptionUnavailable(let version):
            return "Firmware version \(version) is not available for this FlySight."
        case .stackUpdateRequiredButMissingFile(let version):
            return "Firmware version \(version) requires a stack update, but no stack file was provided."
        case .uploadedFileSizeMismatch(let targetPath, let expected, let actual):
            return "Uploaded file \(targetPath) could not be verified. Expected \(expected) bytes, read back \(actual) bytes."
        case .uploadedFileSHA256Mismatch(let targetPath, let expected, let actual):
            return "Uploaded file \(targetPath) could not be verified. Expected SHA-256 \(expected), read back \(actual)."
        }
    }
}

public enum FirmwareUpdateState: Equatable {
    case idle
    case readingStateFile
    case fetchingManifest(includeBeta: Bool)
    case ready(manifest: FirmwareManifest, selectedFirmware: FirmwareOption)
    case downloadingStack(FirmwareFile)
    case downloadingFirmware(FirmwareFile)
    case creatingFirmwareDirectory
    case uploadingStack(FirmwareFile)
    case uploadingFirmware(FirmwareFile)
    case verifyingStack(FirmwareFile)
    case verifyingFirmware(FirmwareFile)
    case requestingInstall
    case completed(FirmwareUpdateResult)
    case failed(message: String)
}

public final class FirmwareUpdateCoordinator {
    public typealias StateObserver = (FirmwareUpdateState) -> Void

    private let client: FirmwareUpdateClientProtocol
    private let bleTransport: FirmwareUpdateBLETransport
    private let stateObserver: StateObserver?

    public private(set) var state: FirmwareUpdateState = .idle
    public private(set) var manifest: FirmwareManifest?
    public private(set) var selectedFirmware: FirmwareOption?

    public init(
        client: FirmwareUpdateClientProtocol = FirmwareUpdateClient(),
        bleTransport: FirmwareUpdateBLETransport,
        stateObserver: StateObserver? = nil
    ) {
        self.client = client
        self.bleTransport = bleTransport
        self.stateObserver = stateObserver
    }

    @discardableResult
    public func loadManifest(includeBeta: Bool = false) async throws -> FirmwareManifest {
        do {
            setState(.readingStateFile)
            let flysightText = try await bleTransport.readFlysightStateFile()

            setState(.fetchingManifest(includeBeta: includeBeta))
            let manifest = try await client.fetchFirmwareOptions(
                flysightText: flysightText,
                includeBeta: includeBeta
            )

            self.manifest = manifest
            selectedFirmware = manifest.recommended
            setState(.ready(manifest: manifest, selectedFirmware: manifest.recommended))
            return manifest
        } catch {
            setFailed(error)
            throw error
        }
    }

    @discardableResult
    public func selectFirmware(version: String) throws -> FirmwareOption {
        guard let manifest = manifest else {
            throw FirmwareUpdateCoordinatorError.noManifestLoaded
        }

        guard let option = manifest.firmwares.first(where: { $0.version == version }) else {
            throw FirmwareUpdateCoordinatorError.firmwareOptionUnavailable(version: version)
        }

        selectedFirmware = option
        setState(.ready(manifest: manifest, selectedFirmware: option))
        return option
    }

    @discardableResult
    public func performUpdate(includeBeta: Bool = false, selectedVersion: String? = nil) async throws -> FirmwareUpdateResult {
        let manifest = try await loadManifest(includeBeta: includeBeta)

        let option: FirmwareOption
        if let selectedVersion = selectedVersion {
            guard let selectedOption = manifest.firmwares.first(where: { $0.version == selectedVersion }) else {
                let error = FirmwareUpdateCoordinatorError.firmwareOptionUnavailable(version: selectedVersion)
                setFailed(error)
                throw error
            }
            option = selectedOption
            selectedFirmware = selectedOption
            setState(.ready(manifest: manifest, selectedFirmware: selectedOption))
        } else {
            option = manifest.recommended
        }

        return try await install(option)
    }

    @discardableResult
    public func installSelectedFirmware() async throws -> FirmwareUpdateResult {
        guard let option = selectedFirmware else {
            let error = FirmwareUpdateCoordinatorError.noManifestLoaded
            setFailed(error)
            throw error
        }

        return try await install(option)
    }

    @discardableResult
    public func install(_ option: FirmwareOption) async throws -> FirmwareUpdateResult {
        do {
            let stackFile = try requiredStackFile(for: option)
            let stackData: Data?

            if let stackFile = stackFile {
                setState(.downloadingStack(stackFile))
                stackData = try await client.downloadAndVerify(stackFile)
            } else {
                stackData = nil
            }

            setState(.downloadingFirmware(option.firmware))
            let firmwareData = try await client.downloadAndVerify(option.firmware)

            setState(.creatingFirmwareDirectory)
            try await bleTransport.ensureFirmwareUpdateDirectory()

            if let stackFile = stackFile, let stackData = stackData {
                setState(.uploadingStack(stackFile))
                try await bleTransport.uploadFirmwareUpdateFile(
                    stackData,
                    targetPath: stackFile.targetPath
                )
                setState(.verifyingStack(stackFile))
                try await verifyUploadedFile(stackFile)
            }

            setState(.uploadingFirmware(option.firmware))
            try await bleTransport.uploadFirmwareUpdateFile(
                firmwareData,
                targetPath: option.firmware.targetPath
            )
            setState(.verifyingFirmware(option.firmware))
            try await verifyUploadedFile(option.firmware)

            setState(.requestingInstall)
            try await bleTransport.installUploadedFirmware()

            let result = FirmwareUpdateResult(
                firmwareVersion: option.version,
                firmwareTargetPath: option.firmware.targetPath,
                stackRequiredVersion: stackFile == nil ? nil : option.stack.requiredVersion,
                stackTargetPath: stackFile?.targetPath,
                stackUploaded: stackFile != nil
            )
            setState(.completed(result))
            return result
        } catch {
            setFailed(error)
            throw error
        }
    }

    private func requiredStackFile(for option: FirmwareOption) throws -> FirmwareFile? {
        guard option.stack.updateRequired else {
            return nil
        }

        guard let file = option.stack.file else {
            throw FirmwareUpdateCoordinatorError.stackUpdateRequiredButMissingFile(version: option.version)
        }

        return file
    }

    private func verifyUploadedFile(_ file: FirmwareFile) async throws {
        let data = try await bleTransport.readFirmwareUpdateFile(
            targetPath: file.targetPath,
            knownSize: file.sizeBytes
        )

        guard data.count == file.sizeBytes else {
            throw FirmwareUpdateCoordinatorError.uploadedFileSizeMismatch(
                targetPath: file.targetPath,
                expected: file.sizeBytes,
                actual: data.count
            )
        }

        let actualSHA256 = FirmwareUpdateClient.sha256Hex(for: data)
        guard actualSHA256 == file.sha256.lowercased() else {
            throw FirmwareUpdateCoordinatorError.uploadedFileSHA256Mismatch(
                targetPath: file.targetPath,
                expected: file.sha256.lowercased(),
                actual: actualSHA256
            )
        }
    }

    private func setState(_ state: FirmwareUpdateState) {
        self.state = state
        stateObserver?(state)
    }

    private func setFailed(_ error: Error) {
        setState(.failed(message: errorMessage(for: error)))
    }

    private func errorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return String(describing: error)
    }
}
