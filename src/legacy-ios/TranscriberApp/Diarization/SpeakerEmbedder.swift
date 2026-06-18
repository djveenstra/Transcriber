import CoreML
import Accelerate
import Foundation

/// Extracts speaker embedding vectors from audio segments using WeSpeaker ResNet34.
/// Each embedding is a 256-dimensional Float vector that characterizes a speaker's voice.
///
/// Input: 16kHz mono audio segment (typically 2-10 seconds)
/// Output: [Float] of length 256 (L2-normalized)
class SpeakerEmbedder {
    private var model: MLModel?

    /// Embedding dimension (WeSpeaker ResNet34 produces 256-dim vectors)
    static let embeddingDimension = 256

    /// Load the WeSpeaker CoreML model.
    func loadModel(path: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all  // Use Neural Engine if available
        model = try MLModel(contentsOf: path, configuration: config)
    }

    /// Extract a speaker embedding from an audio segment.
    /// - Parameter samples: Audio at 16kHz mono Float32, ideally 2-10 seconds long.
    /// - Returns: A 256-dim L2-normalized vector, or nil if extraction fails.
    func extractEmbedding(samples: [Float]) -> [Float]? {
        guard let model = model else { return nil }
        guard !samples.isEmpty else { return nil }

        do {
            // Create MLMultiArray from samples
            // WeSpeaker typically expects shape: [1, num_samples]
            let numSamples = samples.count
            let inputArray = try MLMultiArray(shape: [1, NSNumber(value: numSamples)], dataType: .float32)

            // Copy samples into MLMultiArray
            let ptr = inputArray.dataPointer.bindMemory(to: Float.self, capacity: numSamples)
            samples.withUnsafeBufferPointer { buffer in
                ptr.update(from: buffer.baseAddress!, count: numSamples)
            }

            // Create input feature provider
            let inputFeatures = try MLDictionaryFeatureProvider(
                dictionary: ["audio": MLFeatureValue(multiArray: inputArray)]
            )

            // Run prediction
            let output = try model.prediction(from: inputFeatures)

            // Extract embedding from output
            // WeSpeaker output key is typically "embedding" with shape [1, 256]
            guard let outputArray = output.featureValue(for: "embedding")?.multiArrayValue else {
                return nil
            }

            // Convert to Float array
            var embedding = [Float](repeating: 0, count: Self.embeddingDimension)
            for i in 0..<Self.embeddingDimension {
                embedding[i] = outputArray[i].floatValue
            }

            // L2-normalize the embedding
            normalize(&embedding)

            return embedding
        } catch {
            print("Speaker embedding extraction failed: \(error)")
            return nil
        }
    }

    /// Compute cosine similarity between two L2-normalized embeddings.
    /// Since vectors are normalized, cosine similarity equals the dot product.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }

    // MARK: - Private

    /// L2-normalize a vector in place using Accelerate framework.
    private func normalize(_ vector: inout [Float]) {
        var sumOfSquares: Float = 0
        vDSP_svesq(vector, 1, &sumOfSquares, vDSP_Length(vector.count))
        var norm = sqrt(sumOfSquares)
        guard norm > 0 else { return }
        vDSP_vsdiv(vector, 1, &norm, &vector, 1, vDSP_Length(vector.count))
    }
}
