import AVFoundation
import Foundation

/// Orchestrates the full diarization pipeline: VAD → Segment → Embed → Cluster.
///
/// Input: Path to a 16kHz mono WAV file (the recorded audio).
/// Output: Array of DiarizationSegment (start, end, speakerLabel).
///
/// Steps:
/// 1. Load audio samples from WAV file
/// 2. Run VAD to find speech regions
/// 3. Split speech regions into uniform segments (~3 seconds each)
/// 4. Extract speaker embedding for each segment
/// 5. Cluster embeddings to determine speaker identity
/// 6. Map cluster labels back to time segments
/// 7. Merge consecutive same-speaker segments
class DiarizationPipeline: ObservableObject {
    @Published var progress: Double = 0.0   // 0.0 to 1.0
    @Published var status: String = ""

    private let vad: VoiceActivityDetector
    private let embedder: SpeakerEmbedder
    private let clustering: AgglomerativeClustering

    /// Segment duration for embedding extraction (seconds)
    private let segmentDuration: Double = 3.0

    /// Initialize with model file paths.
    init(vadModelPath: URL, embedderModelPath: URL, clusteringThreshold: Float = 0.75) throws {
        self.vad = VoiceActivityDetector()
        try self.vad.loadModel(path: vadModelPath)
        self.embedder = SpeakerEmbedder()
        try self.embedder.loadModel(path: embedderModelPath)
        self.clustering = AgglomerativeClustering(threshold: clusteringThreshold)
    }

    /// Run diarization on a WAV file. Returns speaker-labeled time segments.
    /// Call from a background Task.
    func run(audioURL: URL) async throws -> [DiarizationSegment] {
        // 1. Load audio
        await updateStatus("Loading audio...", progress: 0.0)
        let samples = try loadWAV(url: audioURL)

        // 2. Voice Activity Detection
        await updateStatus("Detecting speech regions...", progress: 0.1)
        let speechRegions = vad.detectSpeech(samples: samples)

        guard !speechRegions.isEmpty else {
            await updateStatus("No speech detected", progress: 1.0)
            return []
        }

        // 3. Split speech regions into ~3-second segments
        await updateStatus("Segmenting audio...", progress: 0.2)
        let segments = segmentSpeechRegions(speechRegions, from: samples)

        guard !segments.isEmpty else {
            await updateStatus("No segments to process", progress: 1.0)
            return []
        }

        // 4. Extract speaker embeddings
        await updateStatus("Extracting speaker features...", progress: 0.3)
        var embeddings: [[Float]] = []
        for (i, segment) in segments.enumerated() {
            if let embedding = embedder.extractEmbedding(samples: segment.samples) {
                embeddings.append(embedding)
            } else {
                // Zero vector fallback (will cluster separately)
                embeddings.append([Float](repeating: 0, count: SpeakerEmbedder.embeddingDimension))
            }

            // Update progress (embedding extraction is 30-80% of total)
            let embeddingProgress = 0.3 + 0.5 * Double(i + 1) / Double(segments.count)
            await updateProgress(embeddingProgress)
        }

        // 5. Cluster embeddings
        await updateStatus("Identifying speakers...", progress: 0.8)
        let clusterResult = clustering.cluster(embeddings: embeddings)

        // 6. Map cluster labels back to time segments
        await updateStatus("Mapping speakers...", progress: 0.9)
        var diarSegments: [DiarizationSegment] = []
        for (i, segment) in segments.enumerated() {
            diarSegments.append(DiarizationSegment(
                startMs: segment.startMs,
                endMs: segment.endMs,
                speaker: String(format: "SPEAKER_%02d", clusterResult.labels[i])
            ))
        }

        // 7. Merge consecutive same-speaker segments
        await updateStatus("Finalizing...", progress: 0.95)
        let merged = mergeConsecutive(diarSegments)

        await updateStatus("Done", progress: 1.0)
        return merged
    }

    // MARK: - Private Helpers

    /// Segment speech regions into ~3-second windows for embedding extraction.
    private func segmentSpeechRegions(
        _ regions: [(startMs: Int, endMs: Int)],
        from samples: [Float]
    ) -> [(startMs: Int, endMs: Int, samples: [Float])] {
        let segmentMs = Int(segmentDuration * 1000)
        let samplesPerMs = 16  // 16000 / 1000

        var segments: [(startMs: Int, endMs: Int, samples: [Float])] = []

        for region in regions {
            var cursor = region.startMs
            while cursor < region.endMs {
                let endMs = min(cursor + segmentMs, region.endMs)
                let startSample = cursor * samplesPerMs
                let endSample = min(endMs * samplesPerMs, samples.count)

                if endSample > startSample && (endSample - startSample) > samplesPerMs * 500 {
                    // Only include segments longer than 500ms
                    let segSamples = Array(samples[startSample..<endSample])
                    segments.append((startMs: cursor, endMs: endMs, samples: segSamples))
                }
                cursor = endMs
            }
        }

        return segments
    }

    /// Merge consecutive same-speaker segments that are close in time.
    private func mergeConsecutive(_ segments: [DiarizationSegment]) -> [DiarizationSegment] {
        guard var current = segments.first else { return [] }
        var merged: [DiarizationSegment] = []

        for seg in segments.dropFirst() {
            if seg.speaker == current.speaker && (seg.startMs - current.endMs) < 500 {
                // Merge: extend current segment
                current = DiarizationSegment(
                    startMs: current.startMs,
                    endMs: seg.endMs,
                    speaker: current.speaker
                )
            } else {
                merged.append(current)
                current = seg
            }
        }
        merged.append(current)

        return merged
    }

    /// Load a WAV file into a Float32 sample buffer.
    private func loadWAV(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate: 16000,
                                    channels: 1,
                                    interleaved: false)!

        // If the file isn't already 16kHz mono, we need to convert
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: frameCount) else {
            throw DiarizationError.audioLoadFailed
        }
        try file.read(into: buffer)

        // Convert to 16kHz mono if needed
        if file.processingFormat.sampleRate == 16000 && file.processingFormat.channelCount == 1 {
            // Already in the right format
            guard let channelData = buffer.floatChannelData?[0] else {
                throw DiarizationError.audioLoadFailed
            }
            return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        } else {
            // Convert
            guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
                throw DiarizationError.audioLoadFailed
            }
            let ratio = 16000.0 / file.processingFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format,
                                                       frameCapacity: outputFrameCount) else {
                throw DiarizationError.audioLoadFailed
            }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard error == nil, let channelData = outputBuffer.floatChannelData?[0] else {
                throw DiarizationError.audioLoadFailed
            }
            return Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
        }
    }

    @MainActor
    private func updateStatus(_ message: String, progress: Double) {
        self.status = message
        self.progress = progress
    }

    @MainActor
    private func updateProgress(_ value: Double) {
        self.progress = value
    }

    enum DiarizationError: LocalizedError {
        case audioLoadFailed

        var errorDescription: String? {
            switch self {
            case .audioLoadFailed: return "Failed to load audio file for diarization"
            }
        }
    }
}
