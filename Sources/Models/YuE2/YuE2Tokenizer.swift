import Foundation

public final class YuE2Tokenizer: @unchecked Sendable {
    private var tokenToRank: [Data: Int] = [:]
    private var rankToToken: [Int: Data] = [:]

    public static let shared = YuE2Tokenizer()

    public init() {}

    public func load(from fileURL: URL) {
        guard tokenToRank.isEmpty else { return }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            print("[YuE2Tokenizer] Failed to read \(fileURL.path)")
            return
        }
        var map: [Data: Int] = [:]
        map.reserveCapacity(152000)

        for line in content.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count == 2,
                  let data = Data(base64Encoded: String(parts[0])),
                  let rank = Int(parts[1]) else { continue }
            map[data] = rank
        }
        self.tokenToRank = map
        print("[YuE2Tokenizer] Loaded \(map.count) token ranks from \(fileURL.lastPathComponent)")
    }

    public func encode(text: String) -> [Int] {
        guard !tokenToRank.isEmpty else {
            return text.utf8.map { Int($0) }
        }

        // Byte-level BPE
        var byteTokens: [Data] = text.utf8.map { Data([$0]) }
        while byteTokens.count >= 2 {
            var bestIdx: Int? = nil
            var bestRank = Int.max

            for i in 0..<(byteTokens.count - 1) {
                var merged = byteTokens[i]
                merged.append(byteTokens[i + 1])
                if let rank = tokenToRank[merged], rank < bestRank {
                    bestRank = rank
                    bestIdx = i
                }
            }

            guard let idx = bestIdx else { break }
            var merged = byteTokens[idx]
            merged.append(byteTokens[idx + 1])
            byteTokens[idx] = merged
            byteTokens.remove(at: idx + 1)
        }

        return byteTokens.compactMap { tokenToRank[$0] }
    }
}
