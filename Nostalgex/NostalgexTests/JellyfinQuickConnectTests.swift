import XCTest
@testable import Nostalgex

/// Quick Connect starts with POST /QuickConnect/Initiate.
///
/// Measured 2026-10-19 against Jellyfin 12.2.0 with Quick Connect on:
///
///     GET  /QuickConnect/Initiate   ->  405, empty body
///     POST /QuickConnect/Initiate   ->  200 { Code, Secret, ... }
///
/// The app sent a GET (no httpMethod), so Quick Connect could not start on 12.x and the
/// person was told it might be off. Jellyfin's own history (QuickConnectController.cs):
/// 10.7 and 10.8 have only the GET; 10.9 through 10.11 answer both; 12.0 removed the GET.
/// So POST goes first and GET is retried only on 405 or 404, for the older servers.
/// Reported by the Roku port's author, who also confirmed GET /QuickConnect/Connect and
/// POST /Users/AuthenticateWithQuickConnect are right as they are.
@MainActor
final class JellyfinQuickConnectTests: XCTestCase {

    /// Records each request and answers from a script, one entry per request.
    final class Recorder: @unchecked Sendable {
        enum Answer {
            case status(Int, String)
            case failure(URLError.Code)
        }

        private let lock = NSLock()
        private var answers: [Answer]
        private(set) var requests: [URLRequest] = []

        init(_ answers: [Answer]) { self.answers = answers }

        var methods: [String] {
            lock.lock(); defer { lock.unlock() }
            return requests.map { $0.httpMethod ?? "GET" }
        }

        var send: JellyfinAPIService.SignInSend {
            { [self] request in try self.answer(request) }
        }

        private func answer(_ request: URLRequest) throws -> (Data, URLResponse) {
            lock.lock(); defer { lock.unlock() }
            requests.append(request)
            let next = answers.isEmpty ? .status(500, "") : answers.removeFirst()
            switch next {
            case let .failure(code):
                throw URLError(code)
            case let .status(code, body):
                let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (Data(body.utf8), response)
            }
        }
    }

    private let server = "http://192.168.1.50:8096"
    private let initiated = #"{"Authenticated":false,"Secret":"s3cr3t","Code":"123456","DeviceId":"d","DeviceName":"Apple TV","AppName":"Nostalgex","AppVersion":"1.0"}"#

    func testInitiateIsAPost() async throws {
        let recorder = Recorder([.status(200, initiated)])
        let result = try await JellyfinAPIService.quickConnectInitiate(serverURL: server, send: recorder.send)

        XCTAssertEqual(result.code, "123456")
        XCTAssertEqual(result.secret, "s3cr3t")
        XCTAssertEqual(recorder.methods, ["POST"], "Jellyfin 12.x answers a GET to Initiate with 405")
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "\(server)/QuickConnect/Initiate")
        XCTAssertNil(request.httpBody, "Initiate takes no body")
        let auth = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.hasPrefix("MediaBrowser "), auth)
        XCTAssertTrue(auth.contains("DeviceId="), "Jellyfin files the request under the device in this header")
        XCTAssertFalse(auth.contains("Token="), "no token before sign-in")
        XCTAssertEqual(request.timeoutInterval, SignInRequest.timeout)
    }

    // Jellyfin 10.7 and 10.8 route Initiate as GET only.
    func testA405RetriesOnceWithGET() async throws {
        let recorder = Recorder([.status(405, ""), .status(200, initiated)])
        let result = try await JellyfinAPIService.quickConnectInitiate(serverURL: server, send: recorder.send)
        XCTAssertEqual(result.code, "123456")
        XCTAssertEqual(recorder.methods, ["POST", "GET"])
        XCTAssertEqual(Set(recorder.requests.compactMap { $0.url?.absoluteString }), ["\(server)/QuickConnect/Initiate"])
        XCTAssertEqual(recorder.requests.last?.value(forHTTPHeaderField: "Authorization"),
                       recorder.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }

    func testA404RetriesOnceWithGET() async throws {
        let recorder = Recorder([.status(404, ""), .status(200, initiated)])
        _ = try await JellyfinAPIService.quickConnectInitiate(serverURL: server, send: recorder.send)
        XCTAssertEqual(recorder.methods, ["POST", "GET"])
    }

    // Two 404s mean the address isn't Jellyfin. The error must stay a 404 so the sign-in
    // tries the next address and the message says so.
    func testTwo404sStillReadAsTheWrongPlace() async {
        let recorder = Recorder([.status(404, ""), .status(404, "")])
        do {
            _ = try await JellyfinAPIService.quickConnectInitiate(serverURL: server, send: recorder.send)
            XCTFail("expected a 404")
        } catch {
            XCTAssertEqual(error as? PlexAPIService.APIError, .httpFailure(statusCode: 404))
            XCTAssertTrue(AppState.isWrongPlaceError(error))
        }
        XCTAssertEqual(recorder.methods, ["POST", "GET"])
    }

    // Quick Connect switched off is a 401 on every version. One request, and the person
    // is told it is off.
    func testQuickConnectOffIsNotRetried() async {
        let recorder = Recorder([.status(401, ""), .status(200, initiated)])
        do {
            _ = try await JellyfinAPIService.quickConnectInitiate(serverURL: server, send: recorder.send)
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? PlexAPIService.APIError, .unauthorized)
        }
        XCTAssertEqual(recorder.methods, ["POST"])
    }

    func testOtherFailuresAreNotRetried() async {
        for status in [400, 403, 500, 502, 503] {
            let recorder = Recorder([.status(status, ""), .status(200, initiated)])
            _ = try? await JellyfinAPIService.quickConnectInitiate(serverURL: server, send: recorder.send)
            XCTAssertEqual(recorder.methods, ["POST"], "HTTP \(status)")
        }
        for status in [200, 401, 403, 500] {
            XCTAssertFalse(JellyfinAPIService.quickConnectInitiateRetriesWithGET(statusCode: status), "HTTP \(status)")
        }
        XCTAssertTrue(JellyfinAPIService.quickConnectInitiateRetriesWithGET(statusCode: 405))
        XCTAssertTrue(JellyfinAPIService.quickConnectInitiateRetriesWithGET(statusCode: 404))
    }

    // An unreachable server keeps its network error, so the message names the network.
    func testANetworkErrorIsThrownAsIs() async {
        let recorder = Recorder([.failure(.cannotConnectToHost)])
        do {
            _ = try await JellyfinAPIService.quickConnectInitiate(serverURL: server, send: recorder.send)
            XCTFail("expected a URLError")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cannotConnectToHost)
        }
        XCTAssertEqual(recorder.methods, ["POST"])
    }
}

/// Live harness, not a unit test: the whole Quick Connect sign-in against a real Jellyfin,
/// through the app's own `quickConnectInitiate`, `quickConnectCheck` and
/// `quickConnectAuthenticate`. Approving the code stands in for the person in the
/// Jellyfin dashboard and needs a credential that may approve for the user.
///
/// Skipped unless supplied:
///   TEST_RUNNER_NOSTALGEX_JF_URL=http://127.0.0.1:8096
///   TEST_RUNNER_NOSTALGEX_JF_APPROVER_TOKEN=<admin API key, or the user's own token>
///   TEST_RUNNER_NOSTALGEX_JF_USER=<user id to sign in as>
///   TEST_RUNNER_NOSTALGEX_JF_OUT=<file for the transcript> (optional)
/// Prints no token or secret, only their lengths.
final class JellyfinQuickConnectLiveHarness: XCTestCase {
    func testQuickConnectSignInAgainstLocalJellyfin() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["NOSTALGEX_JF_URL"], let approver = env["NOSTALGEX_JF_APPROVER_TOKEN"],
              let user = env["NOSTALGEX_JF_USER"] else {
            throw XCTSkip("No local Jellyfin configured (NOSTALGEX_JF_URL/APPROVER_TOKEN/USER)")
        }
        var out: [String] = []
        func emit(_ s: String) { print(s); out.append(s) }
        defer {
            if let path = env["NOSTALGEX_JF_OUT"] { try? out.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8) }
        }

        let started = try await JellyfinAPIService.quickConnectInitiate(serverURL: server)
        emit("[QC] initiate: code length \(started.code.count), secret length \(started.secret.count)")
        XCTAssertFalse(started.code.isEmpty)

        let before = try await JellyfinAPIService.quickConnectCheck(serverURL: server, secret: started.secret)
        emit("[QC] poll before approval: authenticated=\(before)")
        XCTAssertFalse(before)

        var approve = URLRequest(url: try XCTUnwrap(URL(string:
            "\(server)/QuickConnect/Authorize?code=\(started.code)&userId=\(user)")))
        approve.httpMethod = "POST"
        approve.setValue(JellyfinAPIService.authorizationHeader(deviceID: "nostalgex-qc-harness", token: approver),
                         forHTTPHeaderField: "Authorization")
        let (approvedBody, approvedResponse) = try await URLSession.shared.data(for: approve)
        let approvedStatus = (approvedResponse as? HTTPURLResponse)?.statusCode ?? -1
        emit("[QC] approve: HTTP \(approvedStatus) body \(String(data: approvedBody, encoding: .utf8) ?? "?")")
        XCTAssertEqual(approvedStatus, 200)

        var after = false
        for _ in 0..<10 where !after {
            after = try await JellyfinAPIService.quickConnectCheck(serverURL: server, secret: started.secret)
            if !after { try await Task.sleep(nanoseconds: 300_000_000) }
        }
        emit("[QC] poll after approval: authenticated=\(after)")
        XCTAssertTrue(after)

        let auth = try await JellyfinAPIService.quickConnectAuthenticate(serverURL: server, secret: started.secret)
        emit("[QC] authenticate: token length \(auth.accessToken.count), user matches \(auth.userId == user), server id length \(auth.serverID.count)")
        XCTAssertFalse(auth.accessToken.isEmpty)
        XCTAssertEqual(auth.userId, user)

        let service = JellyfinAPIService(serverURL: server, accessToken: auth.accessToken, userId: auth.userId, serverID: auth.serverID)
        let sections = try await service.loadSections()
        emit("[QC] libraries with the new token: \(sections.count)")
        XCTAssertFalse(sections.isEmpty)
    }
}
