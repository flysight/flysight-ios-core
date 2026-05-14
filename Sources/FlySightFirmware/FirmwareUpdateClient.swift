import CryptoKit
import Foundation

public protocol FirmwareHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: FirmwareHTTPTransport {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data = data, let response = response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }

                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }
}

public struct FirmwareManifest: Equatable {
    public let device: FirmwareDevice
    public let includeBeta: Bool
    public let recommended: FirmwareOption
    public let firmwares: [FirmwareOption]

    public init(
        device: FirmwareDevice,
        includeBeta: Bool,
        recommended: FirmwareOption,
        firmwares: [FirmwareOption]
    ) {
        self.device = device
        self.includeBeta = includeBeta
        self.recommended = recommended
        self.firmwares = firmwares
    }
}

extension FirmwareManifest: Decodable {
    private enum CodingKeys: String, CodingKey {
        case device
        case includeBeta = "include_beta"
        case recommended
        case firmwares
    }
}

public struct FirmwareDevice: Decodable, Equatable {
    public let firmwareVersion: String
    public let stackVersion: String
    public let stackVersionUnknown: Bool
    public let pubkeyX: String
    public let legacy: Bool

    public init(
        firmwareVersion: String,
        stackVersion: String,
        stackVersionUnknown: Bool,
        pubkeyX: String,
        legacy: Bool
    ) {
        self.firmwareVersion = firmwareVersion
        self.stackVersion = stackVersion
        self.stackVersionUnknown = stackVersionUnknown
        self.pubkeyX = pubkeyX
        self.legacy = legacy
    }

    private enum CodingKeys: String, CodingKey {
        case firmwareVersion = "firmware_version"
        case stackVersion = "stack_version"
        case stackVersionUnknown = "stack_version_unknown"
        case pubkeyX = "pubkey_x"
        case legacy
    }
}

public struct FirmwareOption: Decodable, Equatable {
    public let version: String
    public let releaseDate: String
    public let isBeta: Bool
    public let releaseNotesURL: URL?
    public let firmware: FirmwareFile
    public let stack: StackUpdate

    public init(
        version: String,
        releaseDate: String,
        isBeta: Bool,
        releaseNotesURL: URL?,
        firmware: FirmwareFile,
        stack: StackUpdate
    ) {
        self.version = version
        self.releaseDate = releaseDate
        self.isBeta = isBeta
        self.releaseNotesURL = releaseNotesURL
        self.firmware = firmware
        self.stack = stack
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case releaseDate = "release_date"
        case isBeta = "is_beta"
        case releaseNotesURL = "release_notes_url"
        case firmware
        case stack
    }
}

public struct FirmwareFile: Decodable, Equatable {
    public let url: URL
    public let targetPath: String
    public let sizeBytes: Int
    public let sha256: String

    public init(
        url: URL,
        targetPath: String,
        sizeBytes: Int,
        sha256: String
    ) {
        self.url = url
        self.targetPath = targetPath
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case targetPath = "target_path"
        case sizeBytes = "size_bytes"
        case sha256
    }
}

public struct StackUpdate: Decodable, Equatable {
    public let requiredVersion: String
    public let currentVersion: String
    public let currentVersionUnknown: Bool
    public let updateRequired: Bool
    public let file: FirmwareFile?

    public init(
        requiredVersion: String,
        currentVersion: String,
        currentVersionUnknown: Bool,
        updateRequired: Bool,
        file: FirmwareFile?
    ) {
        self.requiredVersion = requiredVersion
        self.currentVersion = currentVersion
        self.currentVersionUnknown = currentVersionUnknown
        self.updateRequired = updateRequired
        self.file = file
    }

    private enum CodingKeys: String, CodingKey {
        case requiredVersion = "required_version"
        case currentVersion = "current_version"
        case currentVersionUnknown = "current_version_unknown"
        case updateRequired = "update_required"
        case file
    }
}

public struct FirmwareEndpointError: Decodable, Error, Equatable {
    public enum KnownCode: String {
        case configTxt = "config_txt"
        case notFlysightTxt = "not_flysight_txt"
        case missingFlysightTxt = "missing_flysight_txt"
        case unsupportedDevice = "unsupported_device"
        case noFirmware = "no_firmware"
        case missingFile = "missing_file"
    }

    public let code: String
    public let message: String
    public let status: Int?

    public var knownCode: KnownCode? {
        KnownCode(rawValue: code)
    }

    public init(code: String, message: String, status: Int?) {
        self.code = code
        self.message = message
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case data
    }

    private enum DataKeys: String, CodingKey {
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)

        if container.contains(.data) {
            let dataContainer = try container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
            status = try dataContainer.decodeIfPresent(Int.self, forKey: .status)
        } else {
            status = nil
        }
    }
}

public enum FirmwareUpdateClientError: Error, Equatable, LocalizedError {
    case invalidResponse
    case endpoint(FirmwareEndpointError, statusCode: Int)
    case httpStatus(Int)
    case emptyFirmwareList
    case downloadSizeMismatch(expected: Int, actual: Int)
    case downloadSHA256Mismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The firmware server returned an invalid response."
        case .endpoint(let error, _):
            return error.message
        case .httpStatus(let status):
            return "The firmware server returned HTTP \(status)."
        case .emptyFirmwareList:
            return "No compatible firmware files were returned."
        case .downloadSizeMismatch(let expected, let actual):
            return "Downloaded file size did not match. Expected \(expected) bytes, got \(actual) bytes."
        case .downloadSHA256Mismatch:
            return "Downloaded file verification failed."
        }
    }
}

public struct FirmwareUpdateClient {
    public static let productionBaseURL = URL(string: "https://flysight.ca/wp-json/flysight/v1/firmware")!

    private let baseURL: URL
    private let transport: FirmwareHTTPTransport
    private let decoder: JSONDecoder

    public init(
        baseURL: URL = FirmwareUpdateClient.productionBaseURL,
        transport: FirmwareHTTPTransport = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.decoder = JSONDecoder()
    }

    public func fetchFirmwareOptions(
        flysightText: String,
        includeBeta: Bool = false
    ) async throws -> FirmwareManifest {
        let request = try makeManifestRequest(flysightText: flysightText, includeBeta: includeBeta)
        let (data, response) = try await transport.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirmwareUpdateClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let endpointError = try? decoder.decode(FirmwareEndpointError.self, from: data) {
                throw FirmwareUpdateClientError.endpoint(endpointError, statusCode: httpResponse.statusCode)
            }
            throw FirmwareUpdateClientError.httpStatus(httpResponse.statusCode)
        }

        let manifest = try decoder.decode(FirmwareManifest.self, from: data)
        guard !manifest.firmwares.isEmpty else {
            throw FirmwareUpdateClientError.emptyFirmwareList
        }
        return manifest
    }

    public func downloadAndVerify(_ file: FirmwareFile) async throws -> Data {
        let request = URLRequest(url: file.url)
        let (data, response) = try await transport.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw FirmwareUpdateClientError.httpStatus(httpResponse.statusCode)
        }

        guard data.count == file.sizeBytes else {
            throw FirmwareUpdateClientError.downloadSizeMismatch(
                expected: file.sizeBytes,
                actual: data.count
            )
        }

        let actualSHA256 = Self.sha256Hex(for: data)
        guard actualSHA256 == file.sha256.lowercased() else {
            throw FirmwareUpdateClientError.downloadSHA256Mismatch(
                expected: file.sha256.lowercased(),
                actual: actualSHA256
            )
        }

        return data
    }

    private func makeManifestRequest(flysightText: String, includeBeta: Bool) throws -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        if includeBeta {
            var queryItems = components?.queryItems ?? []
            queryItems.append(URLQueryItem(name: "include_beta", value: "true"))
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw FirmwareUpdateClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "flysight_txt": flysightText
        ])
        return request
    }

    private static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
