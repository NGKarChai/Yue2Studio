import Foundation
import Tokenizers

public final class YuETokenizer: @unchecked Sendable {
    public private(set) var isLoaded: Bool = false
    private var tokenToId: [String: Int] = [:]
    private var idToToken: [Int: String] = [:]
    private var huggingFaceTokenizer: Tokenizer?

    public init() {
        setupSpecialTokens()
    }

    private func setupSpecialTokens() {
        let specials: [String: Int] = [
            "<EOD>": 32000,
            "<SOA>": 32001,
            "<EOA>": 32002,
            "<SOI>": 32003,
            "<EOI>": 32004,
            "<SOV>": 32005,
            "<EOV>": 32006,
            "<s_local>": 32007,
            "<e_local>": 32008,
            "<s_global>": 32009,
            "<e_global>": 32010,
            "<semantic>": 32011,
            "<acoustic>": 32012,
            "<stage_1>": 32013,
            "<dac_16k>": 32014,
            "<dac_44k>": 32015,
            "<xcodec>": 32016,
            "<stage_2>": 32017
        ]
        for (tok, id) in specials {
            tokenToId[tok] = id
            idToToken[id] = tok
        }
    }

    public func load(from directory: URL) async {
        let tokenizerConfig = directory.appendingPathComponent("tokenizer.json")
        if FileManager.default.fileExists(atPath: tokenizerConfig.path) {
            do {
                self.huggingFaceTokenizer = try await AutoTokenizer.from(modelFolder: directory)
                self.isLoaded = true
                print("[YuETokenizer] Loaded HuggingFace tokenizer from \(directory.path)")
                return
            } catch {
                print("[YuETokenizer] Notice: Could not load AutoTokenizer (\(error)), using built-in byte BPE.")
            }
        }
        self.isLoaded = true
    }

    public func encode(text: String, addBOS: Bool = true) -> [Int] {
        var tokens: [Int] = []
        if let hf = huggingFaceTokenizer {
            tokens = hf.encode(text: text)
        } else {
            // Native fallback tokenization: splits by whitespace and special tokens
            let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

            for word in words {
                if let specialId = tokenToId[word] {
                    tokens.append(specialId)
                } else {
                    // Byte-fallback encoding for text characters
                    for byte in word.utf8 {
                        tokens.append(Int(byte) + 256)
                    }
                }
            }

            if tokens.isEmpty {
                tokens = [32003]
            }
        }

        if !addBOS && tokens.first == 1 {
            tokens.removeFirst()
        }

        return tokens
    }

    public func decode(tokens: [Int]) -> String {
        if let hf = huggingFaceTokenizer {
            return hf.decode(tokens: tokens)
        }

        var chars: [UInt8] = []
        var output = ""

        for id in tokens {
            if let tok = idToToken[id] {
                if !chars.isEmpty {
                    output += String(decoding: chars, as: UTF8.self)
                    chars.removeAll()
                }
                output += tok + " "
            } else if id >= 256 && id < 512 {
                chars.append(UInt8(id - 256))
            }
        }

        if !chars.isEmpty {
            output += String(decoding: chars, as: UTF8.self)
        }

        return output
    }
}
