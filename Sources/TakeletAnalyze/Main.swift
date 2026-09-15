import Foundation
import AnalysisCore
import Darwin

@main struct TakeletAnalyze {
    static func main() async {
        signal(SIGPIPE, SIG_IGN)
        signal(SIGINT) { _ in interrupted = true }
        let args = CommandLine.arguments
        do {
            switch args.dropFirst().first {
            case "prepare" where args.count == 4:
                try await prepare(source: URL(fileURLWithPath: args[2]), destination: URL(fileURLWithPath: args[3]))
            case "probe" where args.count == 3:
                let output = URL(fileURLWithPath: args[2])
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let connection = try connect(work: output)
                defer { connection.rpc.close() }
                try saveObject(connection.snapshot, to: output.appendingPathComponent("connection.json"))
                print("Account: \(connection.accountType). Models: \(connection.models.count). Metadata saved; no inference requested.")
            case "analyze" where args.count == 4 || args.count == 6:
                var cancel: Double?
                if args.count == 6 {
                    guard args[4] == "--cancel-after", let seconds = Double(args[5]), seconds.isFinite, seconds >= 0 else { throw AnalysisError("Invalid cancellation delay") }
                    cancel = seconds
                }
                try analyze(manifestURL: URL(fileURLWithPath: args[2]), output: URL(fileURLWithPath: args[3]), cancelAfter: cancel)
            default:
                throw AnalysisError("Usage: takelet-analyze prepare VIDEO OUTPUT | probe OUTPUT | analyze MANIFEST OUTPUT [--cancel-after SECONDS]")
            }
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            exit(1)
        }
    }
}
