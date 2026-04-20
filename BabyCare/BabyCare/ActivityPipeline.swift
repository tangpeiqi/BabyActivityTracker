import Foundation

@MainActor
final class ActivityPipeline {
    private let inferenceClient: InferenceClient
    private let store: ActivityStore
    private let maxInferenceAttempts: Int
    private let requestGate: InferenceRequestGate

    init(
        inferenceClient: InferenceClient,
        store: ActivityStore,
        maxInferenceAttempts: Int = 2,
        requestGate: InferenceRequestGate = InferenceRequestGate()
    ) {
        self.inferenceClient = inferenceClient
        self.store = store
        self.maxInferenceAttempts = max(1, maxInferenceAttempts)
        self.requestGate = requestGate
    }

    func processPhotoCapture(photoData: Data, capturedAt: Date) async throws -> InferenceResult {
        let fileURL = try persistCaptureData(photoData, ext: "jpg")
        let capture = CaptureEnvelope(
            id: UUID(),
            captureType: .photo,
            capturedAt: capturedAt,
            deviceId: nil,
            localMediaURL: fileURL,
            metadata: ["source": "mwdat_photo"]
        )
        let inference = try await inferWithRetry(from: capture)
        try store.saveEvent(from: capture, inference: inference)
        return inference
    }

    func processVideoSegment(
        manifestURL: URL,
        capturedAt: Date,
        metadata: [String: String]
    ) async throws -> InferenceResult {
        let capture = CaptureEnvelope(
            id: UUID(),
            captureType: .shortVideo,
            capturedAt: capturedAt,
            deviceId: nil,
            localMediaURL: manifestURL,
            metadata: metadata
        )
        let inference = try await inferWithRetry(from: capture)
        try store.saveEvent(from: capture, inference: inference)
        return inference
    }

    private func persistCaptureData(_ data: Data, ext: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PoLCaptures", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func inferWithRetry(from capture: CaptureEnvelope) async throws -> InferenceResult {
        try await requestGate.waitForTurn()

        do {
            let inference = try await performInferenceWithRetry(from: capture)
            await requestGate.finish()
            return inference
        } catch {
            await requestGate.finish(cooldownSeconds: cooldownSeconds(after: error))
            throw error
        }
    }

    private func performInferenceWithRetry(from capture: CaptureEnvelope) async throws -> InferenceResult {
        var attempt = 1
        var lastError: Error?

        while attempt <= maxInferenceAttempts {
            do {
                return try await inferenceClient.infer(from: capture)
            } catch {
                lastError = error
                if attempt == maxInferenceAttempts || !shouldRetry(error) {
                    break
                }

                let backoffNanoseconds = UInt64(pow(2.0, Double(attempt - 1)) * 500_000_000)
                try await Task.sleep(nanoseconds: backoffNanoseconds)
                attempt += 1
            }
        }

        throw lastError ?? NSError(
            domain: "ActivityPipeline",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Inference failed after retries."]
        )
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if let geminiError = error as? GeminiInferenceError {
            return geminiError.isRetryableHTTPError
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }

    private func cooldownSeconds(after error: Error) -> TimeInterval? {
        guard let geminiError = error as? GeminiInferenceError, geminiError.isRateLimitError else {
            return nil
        }
        return max(geminiError.retryAfterSeconds ?? 60, 60)
    }
}

actor InferenceRequestGate {
    private let minSpacingSeconds: TimeInterval
    private var isRunning: Bool = false
    private var nextAvailableAt: Date = .distantPast

    init(minSpacingSeconds: TimeInterval = 1.5) {
        self.minSpacingSeconds = minSpacingSeconds
    }

    func waitForTurn() async throws {
        while true {
            let now = Date()
            if !isRunning, now >= nextAvailableAt {
                isRunning = true
                return
            }

            let waitSeconds: TimeInterval
            if isRunning {
                waitSeconds = 0.25
            } else {
                waitSeconds = max(0.25, nextAvailableAt.timeIntervalSince(now))
            }
            try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
        }
    }

    func finish(cooldownSeconds: TimeInterval? = nil) {
        isRunning = false
        let spacing = max(minSpacingSeconds, cooldownSeconds ?? 0)
        nextAvailableAt = Date().addingTimeInterval(spacing)
    }
}
