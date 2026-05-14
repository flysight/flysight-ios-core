import Foundation
@testable import FlySightFirmware
import XCTest

final class FirmwareUpdateClientTests: XCTestCase {
    func testFetchFirmwareOptionsDecodesSuccessfulManifest() async throws {
        let transport = MockFirmwareTransport { request in
            (
                Self.sampleManifestJSON(includeBeta: false),
                Self.httpResponse(for: request.url!, statusCode: 200)
            )
        }
        let client = FirmwareUpdateClient(baseURL: Self.endpointURL, transport: transport)

        let manifest = try await client.fetchFirmwareOptions(flysightText: "Firmware_Ver: v2024.12.30.8;")

        XCTAssertEqual(manifest.device.firmwareVersion, "v2024.12.30.8")
        XCTAssertEqual(manifest.device.stackVersion, "1.19.0")
        XCTAssertFalse(manifest.device.stackVersionUnknown)
        XCTAssertEqual(manifest.device.pubkeyX, String(repeating: "a", count: 64))
        XCTAssertFalse(manifest.device.legacy)
        XCTAssertFalse(manifest.includeBeta)
        XCTAssertEqual(manifest.recommended.version, "v2024.12.30.8")
        XCTAssertEqual(manifest.firmwares.count, 1)
        XCTAssertEqual(manifest.firmwares[0].firmware.targetPath, "FW/APP.SFB")
        XCTAssertFalse(manifest.firmwares[0].stack.updateRequired)
        XCTAssertNil(manifest.firmwares[0].stack.file)
    }

    func testFetchFirmwareOptionsFormsBetaRequestAndBody() async throws {
        let flysightText = "Firmware_Ver: v2024.12.30.8;\nPubkey_X: \(String(repeating: "b", count: 64));"
        let transport = MockFirmwareTransport { request in
            (
                Self.sampleManifestJSON(includeBeta: true),
                Self.httpResponse(for: request.url!, statusCode: 200)
            )
        }
        let client = FirmwareUpdateClient(baseURL: Self.endpointURL, transport: transport)

        _ = try await client.fetchFirmwareOptions(flysightText: flysightText, includeBeta: true)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems, [
            URLQueryItem(name: "include_beta", value: "true")
        ])

        let body = try XCTUnwrap(request.httpBody)
        let jsonObject = try JSONSerialization.jsonObject(with: body) as? [String: String]
        XCTAssertEqual(jsonObject?["flysight_txt"], flysightText)
    }

    func testFetchFirmwareOptionsDecodesEndpointErrors() async throws {
        let cases: [(code: String, status: Int, knownCode: FirmwareEndpointError.KnownCode)] = [
            ("config_txt", 400, .configTxt),
            ("not_flysight_txt", 400, .notFlysightTxt),
            ("unsupported_device", 404, .unsupportedDevice),
        ]

        for testCase in cases {
            let transport = MockFirmwareTransport { request in
                (
                    Self.endpointErrorJSON(code: testCase.code, status: testCase.status),
                    Self.httpResponse(for: request.url!, statusCode: testCase.status)
                )
            }
            let client = FirmwareUpdateClient(baseURL: Self.endpointURL, transport: transport)

            do {
                _ = try await client.fetchFirmwareOptions(flysightText: "bad")
                XCTFail("Expected endpoint error for \(testCase.code)")
            } catch FirmwareUpdateClientError.endpoint(let endpointError, let statusCode) {
                XCTAssertEqual(statusCode, testCase.status)
                XCTAssertEqual(endpointError.code, testCase.code)
                XCTAssertEqual(endpointError.status, testCase.status)
                XCTAssertEqual(endpointError.knownCode, testCase.knownCode)
            } catch {
                XCTFail("Unexpected error for \(testCase.code): \(error)")
            }
        }
    }

    func testDownloadAndVerifyReturnsDataForMatchingMetadata() async throws {
        let data = Data("hello".utf8)
        let file = FirmwareFile(
            url: URL(string: "https://example.com/APP.SFB")!,
            targetPath: "FW/APP.SFB",
            sizeBytes: data.count,
            sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        let transport = MockFirmwareTransport { request in
            (data, Self.httpResponse(for: request.url!, statusCode: 200))
        }
        let client = FirmwareUpdateClient(baseURL: Self.endpointURL, transport: transport)

        let downloadedData = try await client.downloadAndVerify(file)

        XCTAssertEqual(downloadedData, data)
        XCTAssertEqual(transport.requests.first?.url, file.url)
    }

    func testDownloadAndVerifyFailsWhenSizeMismatches() async throws {
        let data = Data("hello".utf8)
        let file = FirmwareFile(
            url: URL(string: "https://example.com/APP.SFB")!,
            targetPath: "FW/APP.SFB",
            sizeBytes: data.count + 1,
            sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        let transport = MockFirmwareTransport { request in
            (data, Self.httpResponse(for: request.url!, statusCode: 200))
        }
        let client = FirmwareUpdateClient(baseURL: Self.endpointURL, transport: transport)

        do {
            _ = try await client.downloadAndVerify(file)
            XCTFail("Expected size mismatch")
        } catch FirmwareUpdateClientError.downloadSizeMismatch(let expected, let actual) {
            XCTAssertEqual(expected, data.count + 1)
            XCTAssertEqual(actual, data.count)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDownloadAndVerifyFailsWhenSHA256Mismatches() async throws {
        let data = Data("hello".utf8)
        let file = FirmwareFile(
            url: URL(string: "https://example.com/APP.SFB")!,
            targetPath: "FW/APP.SFB",
            sizeBytes: data.count,
            sha256: String(repeating: "0", count: 64)
        )
        let transport = MockFirmwareTransport { request in
            (data, Self.httpResponse(for: request.url!, statusCode: 200))
        }
        let client = FirmwareUpdateClient(baseURL: Self.endpointURL, transport: transport)

        do {
            _ = try await client.downloadAndVerify(file)
            XCTFail("Expected SHA-256 mismatch")
        } catch FirmwareUpdateClientError.downloadSHA256Mismatch(let expected, let actual) {
            XCTAssertEqual(expected, String(repeating: "0", count: 64))
            XCTAssertEqual(actual, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static let endpointURL = URL(string: "https://example.com/wp-json/flysight/v1/firmware")!

    private static func httpResponse(for url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private static func sampleManifestJSON(includeBeta: Bool) -> Data {
        Data("""
        {
          "device": {
            "firmware_version": "v2024.12.30.8",
            "stack_version": "1.19.0",
            "stack_version_unknown": false,
            "pubkey_x": "\(String(repeating: "a", count: 64))",
            "legacy": false
          },
          "include_beta": \(includeBeta ? "true" : "false"),
          "recommended": {
            "version": "v2024.12.30.8",
            "release_date": "2026-03-06",
            "is_beta": false,
            "release_notes_url": "https://example.com/release-notes.html",
            "firmware": {
              "url": "https://example.com/APP.SFB",
              "target_path": "FW/APP.SFB",
              "size_bytes": 5,
              "sha256": "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
            },
            "stack": {
              "required_version": "1.19.0",
              "current_version": "1.19.0",
              "current_version_unknown": false,
              "update_required": false,
              "file": null
            }
          },
          "firmwares": [
            {
              "version": "v2024.12.30.8",
              "release_date": "2026-03-06",
              "is_beta": false,
              "release_notes_url": "https://example.com/release-notes.html",
              "firmware": {
                "url": "https://example.com/APP.SFB",
                "target_path": "FW/APP.SFB",
                "size_bytes": 5,
                "sha256": "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
              },
              "stack": {
                "required_version": "1.19.0",
                "current_version": "1.19.0",
                "current_version_unknown": false,
                "update_required": false,
                "file": null
              }
            }
          ]
        }
        """.utf8)
    }

    private static func endpointErrorJSON(code: String, status: Int) -> Data {
        Data("""
        {
          "code": "\(code)",
          "message": "Endpoint error",
          "data": {
            "status": \(status)
          }
        }
        """.utf8)
    }
}

private final class MockFirmwareTransport: FirmwareHTTPTransport {
    typealias Handler = (URLRequest) throws -> (Data, URLResponse)

    private let handler: Handler
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return try handler(request)
    }
}
