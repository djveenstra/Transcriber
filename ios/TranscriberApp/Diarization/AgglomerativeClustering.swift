import Accelerate
import Foundation

/// Result of clustering speaker embeddings.
struct ClusterResult {
    let labels: [Int]       // Cluster label for each input segment (0-indexed)
    let numClusters: Int    // Total number of speakers found
}

/// Agglomerative hierarchical clustering for speaker embeddings.
/// Groups embedding vectors into speaker clusters based on cosine similarity.
///
/// Algorithm:
/// 1. Start with each segment as its own cluster
/// 2. Compute pairwise cosine similarity between all cluster centroids
/// 3. Merge the two most similar clusters (highest similarity)
/// 4. Repeat until the highest similarity drops below a threshold
///
/// This is the same approach pyannote uses internally for speaker clustering.
class AgglomerativeClustering {
    /// Similarity threshold. Two clusters merge only if their similarity exceeds this.
    /// - 0.75 is a good default for speaker diarization
    /// - Lower values → more aggressive merging (fewer speakers detected)
    /// - Higher values → less merging (more speakers detected)
    let threshold: Float

    init(threshold: Float = 0.75) {
        self.threshold = threshold
    }

    /// Cluster embeddings into speaker groups.
    ///
    /// - Parameter embeddings: Array of N speaker embeddings, each of dimension D.
    ///   Embeddings should be L2-normalized (output of SpeakerEmbedder).
    /// - Returns: ClusterResult with a label per embedding and total cluster count.
    ///
    /// Time complexity: O(N^2) per merge step, O(N^3) worst case total.
    /// N is typically small (number of ~3-second speech segments, usually < 1200 for 60 min).
    func cluster(embeddings: [[Float]]) -> ClusterResult {
        let n = embeddings.count
        if n == 0 { return ClusterResult(labels: [], numClusters: 0) }
        if n == 1 { return ClusterResult(labels: [0], numClusters: 1) }

        // Each element starts as its own cluster
        var clusterAssignment = Array(0..<n)
        var clusterCentroids = embeddings
        var clusterSizes = [Int](repeating: 1, count: n)
        var activeClusters = Set(0..<n)

        while activeClusters.count > 1 {
            // Find the pair of active clusters with highest cosine similarity
            var bestSim: Float = -1.0
            var bestI = -1
            var bestJ = -1

            let active = Array(activeClusters).sorted()
            for i in 0..<active.count {
                for j in (i + 1)..<active.count {
                    let sim = SpeakerEmbedder.cosineSimilarity(
                        clusterCentroids[active[i]],
                        clusterCentroids[active[j]]
                    )
                    if sim > bestSim {
                        bestSim = sim
                        bestI = active[i]
                        bestJ = active[j]
                    }
                }
            }

            // Stop if best similarity is below threshold
            if bestSim < threshold { break }

            // Merge cluster bestJ into cluster bestI
            let sizeI = Float(clusterSizes[bestI])
            let sizeJ = Float(clusterSizes[bestJ])
            let totalSize = sizeI + sizeJ

            // Update centroid as weighted average
            let dim = clusterCentroids[bestI].count
            var newCentroid = [Float](repeating: 0, count: dim)
            for d in 0..<dim {
                newCentroid[d] = (clusterCentroids[bestI][d] * sizeI +
                                  clusterCentroids[bestJ][d] * sizeJ) / totalSize
            }

            // L2-normalize the new centroid
            var norm: Float = 0
            vDSP_svesq(newCentroid, 1, &norm, vDSP_Length(newCentroid.count))
            norm = sqrt(norm)
            if norm > 0 {
                vDSP_vsdiv(newCentroid, 1, &norm, &newCentroid, 1, vDSP_Length(newCentroid.count))
            }

            clusterCentroids[bestI] = newCentroid
            clusterSizes[bestI] = Int(totalSize)
            activeClusters.remove(bestJ)

            // Reassign all segments in cluster bestJ to cluster bestI
            for i in 0..<n {
                if clusterAssignment[i] == bestJ {
                    clusterAssignment[i] = bestI
                }
            }
        }

        // Remap cluster IDs to contiguous 0..<numClusters
        let uniqueLabels = Array(Set(clusterAssignment)).sorted()
        let remapping = Dictionary(uniqueKeysWithValues: uniqueLabels.enumerated().map { ($1, $0) })
        let finalLabels = clusterAssignment.map { remapping[$0]! }

        return ClusterResult(labels: finalLabels, numClusters: uniqueLabels.count)
    }
}
