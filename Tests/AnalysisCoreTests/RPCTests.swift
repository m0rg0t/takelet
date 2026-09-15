import Foundation
import XCTest
@testable import AnalysisCore

final class RPCTests: XCTestCase {
    func testMissingExecutableIsRecoverable() {
        XCTAssertThrowsError(try RPC(executable: "/not-a-real-codex-binary", arguments: [], cwd: FileManager.default.temporaryDirectory))
    }
    func mock(_ body: String, run: (RPC) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("server.py")
        try ("import sys,json,time\nmessage=json.loads(sys.stdin.readline())\n" + body).write(to: script, atomically: true, encoding: .utf8)
        let rpc = try RPC(executable: "/usr/bin/env", arguments: ["python3", script.path], cwd: root)
        defer { rpc.close() }
        try run(rpc)
    }
    func testSplitMessagesAndInterleavedEvents() throws {
        try mock("""
        sys.stdout.write('{"method":"turn/started","params":{}}\\n')
        sys.stdout.flush()
        response=json.dumps({'id':message['id'],'result':{'ok':True}})+'\\n'
        for part in [response[:7],response[7:]]:
            sys.stdout.write(part)
            sys.stdout.flush()
            time.sleep(0.02)
        """) { rpc in
            XCTAssertEqual(try rpc.request("test")["ok"] as? Bool, true)
            XCTAssertEqual(try rpc.nextEvent()?["method"] as? String, "turn/started")
        }
    }
    func testRemoteFailurePreservesMeaning() throws {
        try mock("print(json.dumps({'id':message['id'],'error':{'code':429,'message':'Rate limit reached'}}),flush=True)") { rpc in
            XCTAssertThrowsError(try rpc.request("test")) { error in
                XCTAssertTrue(String(describing: error).contains("Rate limit reached"))
            }
        }
    }
    func testUnexpectedApprovalRequestFailsClosed() throws {
        try mock("print(json.dumps({'id':99,'method':'item/commandExecution/requestApproval','params':{}}),flush=True)\ntime.sleep(1)") { rpc in
            XCTAssertThrowsError(try rpc.request("test")) { error in
                XCTAssertTrue(String(describing: error).contains("Unexpected app-server request"))
            }
        }
    }
    func testEOFAndMalformedTransportDoNotHang() throws {
        try mock("sys.exit(0)") { rpc in XCTAssertThrowsError(try rpc.request("test", timeout: 1)) }
        try mock("print('not json',flush=True)") { rpc in XCTAssertThrowsError(try rpc.request("test", timeout: 1)) }
    }
    func testTimeoutIsBounded() throws {
        try mock("time.sleep(10)") { rpc in
            let start = Date()
            XCTAssertThrowsError(try rpc.request("test", timeout: 0.1))
            XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        }
    }
}
