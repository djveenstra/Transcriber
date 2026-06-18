import CoreML
import Foundation

/// Silero VAD v5 running on CoreML.
/// Detects which portions of audio contain speech vs. silence.
///
/// Input: 16kHz mono audio in 512-sample chunks (32ms each)
/// Output: Speech probability (0.0 to 1.0) per chunk
///
/// Usage: feed full audio buffer, get back list of speech regions (startMs, endMs).
class VoiceActivityDetector {
    private var model: MLModel?

    /// Speech probability threshold. Frames above this are considered speech.
    let threshold: Float

    /// Minimum speech duration in milliseconds. Shorter regions are discarded.
    let minSpeechDurationMs: Int

    /// Maximum gap in milliseconds between speech regions before they're split.
    let maxGapMs: Int

    init(threshold: Float = 0.5, minSpeechDurationMs: Int = 250, maxGapMs: Int = 300) {
        self.threshold = threshold
        self.minSpeechDurationMs = minSpeechDurationMs
        self.maxGapMs = maxGapMs
    }

    /// Load the Silero VAD CoreML model from disk.
    func loadModel(path: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all  // Use Neural Engine if available
        model = try MLModel(contentsOf: path, configuration: config)
    }

    /// Detect speech regions in audio samples (16kHz mono Float32).
    /// - Parameter samples: Full audio buffer at 16kHz
    /// - Returns: List of (startMs, endMs) tuples where speech was detected
    func detectSpeech(samples: [Float]) -> [(startMs: Int, endMs: Int)] {
        guard model != nil else { return [] }

        let windowSize = 512        // Silero VAD window size
        let msPerWindow = 32        // 512 / 16000 * 1000
        let sampleRate = 16000

        var probabilities: [Float] = []

        // Process audio in 512-sample windows
        var windowIndex = 0
        while windowIndex * windowSize + windowSize <= samples.count {
            let start = windowIndex * windowSize
            let window = Array(samples[start..<start + windowSize])
            let probability = predict(window: window)
            probabilities.append(probability)
            windowIndex += 1
        }

        // Convert probabilities to speech regions
        var regions: [(startMs: Int, endMs: Int)] = []
        var speechStart: Int? = nil

        for (i, prob) in probabilities.enumerated() {
            let currentMs = i * msPerWindow

            if prob >= threshold {
                if speechStart == nil {
                    speechStart = currentMs
                }
            } else {
                if let start = speechStart {
                    let duration = currentMs - start
                    if duration >= minSpeechDurationMs {
                        regions.append((startMs: start, endMs: currentMs))
                    }
                    speechStart = nil
                }
            }
        }

        // Close final region if still in speech
        if let start = speechStart {
            let endMs = probabilities.count * msPerWindow
            let duration = endMs - start
            if duration >= minSpeechDurationMs {
                regions.append((startMs: start, endMs: endMs))
            }
        }

        // Merge close regions
        return mergeCloseRegions(regions)
    }

    // MARK: - Private

    /// Run the CoreML model on a single 512-sample window.
    /// Returns speech probability (0.0 to 1.0).
    private func predict(window: [Float]) -> Float {
        guard let model = model else { return 0.0 }

        do {
            // Create MLMultiArray for input
            // Silero VAD expects input shape: [1, 512] (batch_size, samples)
            let inputArray = try MLMultiArray(shape: [1, 512], dataType: .float32)
            for i in 0..<min(window.count, 512) {
                inputArray[i] = NSNumber(value: window[i])
            }

            // Create input feature provider
            let inputFeatures = try MLDictionaryFeatureProvider(
                dictionary: ["input": MLFeatureValue(multiArray: inputArray)]
            )

            // Run prediction
            let output = try model.prediction(from: inputFeatures)

            // Extract probability from output
            // Silero VAD output key is typically "output" with shape [1, 1]
            if let outputArray = output.featureValue(for: "output")?.multiArrayValue {
                return outputArray[0].floatValue
            }

            return 0.0
        } catch {
            return 0.0
        }
    }

    /// Merge speech regions that are within maxGapMs of each other.
    private func mergeCloseRegions(_ regions: [(startMs: Int, endMs: Int)]) -> [(startMs: Int, endMs: Int)] {
        guard var current = regions.first else { return [] }
        var merged: [(startMs: Int, endMs: Int)] = []

        for region in regions.dropFirst() {
            if region.startMs - current.endMs <= maxGapMs {
                // Merge: extend current region
                current = (startMs: current.startMs, endMs: region.endMs)
            } else {
                merged.append(current)
                current = region
            }
        }
        merged.append(current)

        return merged
    }
}
