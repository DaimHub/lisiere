import Foundation

struct CodexModel: Identifiable, Hashable, Sendable {
    let slug: String
    let displayName: String

    var id: String { slug }
}

/// Progress reported while Codex works, reduced to what the Studio pane shows.
enum CodexEvent: Sendable, Equatable {
    case progress(String)
    case message(String)
    case filesChanged
}

enum CodexError: LocalizedError {
    case notInstalled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Codex isn't installed. Run `npm install -g @openai/codex`, then `codex login`."
        case .failed(let message):
            message
        }
    }
}

/// Runs the Codex CLI the same way the Codex SDK does: `codex exec --json`, reading JSONL events.
enum Codex {
    struct Launch: Sendable {
        let executable: URL
        let environment: [String: String]
    }

    @MainActor private static var cachedLaunch: Launch?

    @MainActor static func launch() async throws -> Launch {
        if let cachedLaunch { return cachedLaunch }
        guard let launch = await Task.detached(operation: { resolveLaunch() }).value else {
            throw CodexError.notInstalled
        }
        cachedLaunch = launch
        return launch
    }

    /// Asks Codex for the models this account can use, in Codex's own order.
    @MainActor static func models() async throws -> [CodexModel] {
        let launch = try await launch()
        let output = await Task.detached {
            ShellCommand.run(launch.executable.path, ["debug", "models"], environment: launch.environment, timeout: 20)
        }.value
        guard let data = output?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }

        return models
            .filter { ($0["visibility"] as? String) == "list" }
            .sorted { ($0["priority"] as? Int ?? .max) < ($1["priority"] as? Int ?? .max) }
            .compactMap { model in
                guard let slug = model["slug"] as? String else { return nil }
                return CodexModel(slug: slug, displayName: model["display_name"] as? String ?? slug)
            }
    }

    /// Runs one Codex turn in `directory`. The stream finishes when the turn completes and throws when it fails.
    @MainActor static func run(prompt: String, in directory: URL, model: String?) -> AsyncThrowingStream<CodexEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    let launch = try await launch()
                    var arguments = ["exec", "--json", "--skip-git-repo-check",
                                     "--sandbox", "workspace-write",
                                     "--cd", directory.path,
                                     "-c", #"model_reasoning_effort="low""#]
                    if let model, !model.isEmpty {
                        arguments += ["--model", model]
                    }
                    arguments.append("-")

                    let run = try CodexProcess(launch: launch, arguments: arguments, directory: directory,
                                               continuation: continuation)
                    continuation.onTermination = { _ in run.stop() }
                    try run.start(input: prompt)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func resolveLaunch() -> Launch? {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"

        // Apps opened from Finder don't get the PATH that shell startup files build, which is
        // where npm, bun, and Homebrew put `codex` and the Node runtime its launcher needs.
        let script = #"printf '\n__ATHAS_PATH__%s\n__ATHAS_CODEX__%s\n' "$PATH" "$(command -v codex)""#
        var codexPath: String?
        if let output = ShellCommand.run(shell, ["-ilc", script], environment: environment, timeout: 10) {
            for line in output.split(whereSeparator: \.isNewline) {
                if line.hasPrefix("__ATHAS_PATH__") {
                    environment["PATH"] = String(line.dropFirst("__ATHAS_PATH__".count))
                } else if line.hasPrefix("__ATHAS_CODEX__") {
                    let path = String(line.dropFirst("__ATHAS_CODEX__".count))
                    if path.hasPrefix("/") { codexPath = path }
                }
            }
        }

        let candidates = [codexPath, "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                          "\(home)/.bun/bin/codex", "\(home)/.npm-global/bin/codex", "\(home)/.local/bin/codex"]
        guard let path = candidates.compactMap({ $0 }).first(where: FileManager.default.isExecutableFile) else {
            return nil
        }

        let pathEntries = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let extraEntries = [directory, "/opt/homebrew/bin", "/usr/local/bin"].filter { !pathEntries.contains($0) }
        environment["PATH"] = (pathEntries + extraEntries).joined(separator: ":")
        return Launch(executable: URL(fileURLWithPath: path), environment: environment)
    }
}

/// One running `codex exec`, translating its JSONL output into `CodexEvent`s.
private final class CodexProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let continuation: AsyncThrowingStream<CodexEvent, Error>.Continuation
    private let lock = NSLock()
    private var buffer = Data()
    private var errorText = ""
    private var didComplete = false
    private var failure: String?
    private var lastError: String?

    init(launch: Codex.Launch, arguments: [String], directory: URL,
         continuation: AsyncThrowingStream<CodexEvent, Error>.Continuation) throws {
        self.continuation = continuation
        process.executableURL = launch.executable
        process.arguments = arguments
        process.environment = launch.environment
        process.currentDirectoryURL = directory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput
    }

    func start(input prompt: String) throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        errorOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self, let text = String(data: handle.availableData, encoding: .utf8) else { return }
            self.lock.withLock { self.errorText = String((self.errorText + text).suffix(2000)) }
        }
        process.terminationHandler = { [weak self] process in
            self?.finish(status: process.terminationStatus)
        }
        try process.run()
        input.fileHandleForWriting.write(Data(prompt.utf8))
        try? input.fileHandleForWriting.close()
    }

    func stop() {
        if process.isRunning { process.terminate() }
    }

    private func consume(_ data: Data) {
        let lines: [Data] = lock.withLock {
            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return lines
        }
        for line in lines {
            if let event = parse(line) { continuation.yield(event) }
        }
    }

    private func finish(status: Int32) {
        output.fileHandleForReading.readabilityHandler = nil
        errorOutput.fileHandleForReading.readabilityHandler = nil
        consume(output.fileHandleForReading.readDataToEndOfFile())
        consume(Data("\n".utf8))

        let (didComplete, failure, lastError, errorText) = lock.withLock {
            (self.didComplete, self.failure, self.lastError, self.errorText)
        }
        if didComplete {
            continuation.finish()
        } else {
            let detail = failure ?? lastError
                ?? errorText.split(whereSeparator: \.isNewline).last.map(String.init)
                ?? "Codex stopped unexpectedly (exit status \(status))."
            continuation.finish(throwing: CodexError.failed(detail))
        }
    }

    private func parse(_ line: Data) -> CodexEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = json["type"] as? String else { return nil }

        switch type {
        case "turn.completed":
            lock.withLock { didComplete = true }
        case "turn.failed":
            let message = (json["error"] as? [String: Any])?["message"] as? String
            lock.withLock { failure = Self.readableError(message) }
        case "error":
            lock.withLock { lastError = Self.readableError(json["message"] as? String) }
        case "item.started", "item.updated", "item.completed":
            guard let item = json["item"] as? [String: Any] else { return nil }
            return itemEvent(item, isCompleted: type == "item.completed")
        default:
            break
        }
        return nil
    }

    private func itemEvent(_ item: [String: Any], isCompleted: Bool) -> CodexEvent? {
        switch item["type"] as? String {
        case "agent_message":
            guard isCompleted, let text = item["text"] as? String else { return nil }
            return .message(text)
        case "reasoning":
            return .progress("Thinking")
        case "command_execution":
            return isCompleted ? nil : .progress("Running commands")
        case "file_change":
            guard isCompleted else {
                let paths = (item["changes"] as? [[String: Any]])?.compactMap { $0["path"] as? String } ?? []
                let names = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
                return .progress(names.isEmpty ? "Writing files" : "Writing \(names.joined(separator: ", "))")
            }
            return .filesChanged
        case "todo_list":
            return .progress("Planning")
        case "web_search":
            return .progress("Searching the web")
        default:
            return nil
        }
    }

    /// Codex often wraps API errors as JSON inside the message; surface the innermost text.
    private static func readableError(_ message: String?) -> String? {
        guard let message else { return nil }
        if let data = message.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let inner = (json["error"] as? [String: Any])?["message"] as? String ?? json["message"] as? String {
            return inner
        }
        return message
    }
}

/// Runs a short command and returns its standard output, or `nil` if it fails or times out.
enum ShellCommand {
    static func run(_ executable: String, _ arguments: [String], environment: [String: String],
                    timeout: TimeInterval) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let collected = OutputCollector()
        output.fileHandleForReading.readabilityHandler = { collected.append($0.availableData) }
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do { try process.run() } catch { return nil }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        // Background jobs started by shell startup files can keep the pipe open, so drain what's
        // buffered without waiting for end-of-file.
        output.fileHandleForReading.readabilityHandler = nil
        let descriptor = output.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(descriptor, &chunk, chunk.count)
            guard count > 0 else { break }
            collected.append(Data(chunk[0..<count]))
        }
        return String(data: collected.data, encoding: .utf8)
    }

    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()

        var data: Data { lock.withLock { storage } }

        func append(_ data: Data) {
            lock.withLock { storage.append(data) }
        }
    }
}
