import Foundation

final class ProcessRunner {
    func run(
        executable: URL,
        arguments: [String],
        workingDir: URL?,
        environment: [String: String]? = nil,
        onLine: @escaping (String) -> Void
    ) async -> Int32 {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            let proc = Process()
            proc.executableURL = executable
            proc.arguments = arguments
            if let wd = workingDir { proc.currentDirectoryURL = wd }
            if let env = environment {
                var merged = ProcessInfo.processInfo.environment
                for (k, v) in env { merged[k] = v }
                proc.environment = merged
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let s = String(data: data, encoding: .utf8) { onLine(s) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let s = String(data: data, encoding: .utf8) { onLine(s) }
            }

            proc.terminationHandler = { p in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: p.terminationStatus)
            }

            do {
                try proc.run()
            } catch {
                onLine("Failed to start \(executable.lastPathComponent): \(error.localizedDescription)\n")
                continuation.resume(returning: -1)
            }
        }
    }
}
