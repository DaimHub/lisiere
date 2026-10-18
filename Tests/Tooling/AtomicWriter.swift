import Foundation

/// Separate process for SIGKILL acceptance of the production StoreFile implementation.
@main
struct AtomicWriter {
    struct Snapshot: Codable {
        let sequence: Int
        let payload: Data
    }
    static func main() throws {
        let file = StoreFile(url: URL(filePath: CommandLine.arguments[1]))
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        for sequence in 1...100_000 {
            let data = try encoder.encode(Snapshot(sequence: sequence, payload: Data(repeating: UInt8(sequence % 251), count: 1_048_576)))
            try file.writeNow(data).get()
            if sequence == 1 { print("ready"); fflush(stdout) }
        }
    }
}
