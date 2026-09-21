import Foundation

public struct PromptFormatter {
    public static let genreHeader = "[Genre]"
    public static let startOfSegment = "[start_of_segment]"
    public static let endOfSegment = "[end_of_segment]"
    public static let startOfReference = "[start_of_reference]"
    public static let endOfReference = "[end_of_reference]"

    private static let standardSectionKeywords: [String: String] = [
        "intro": "[intro]",
        "verse": "[verse]",
        "chorus": "[chorus]",
        "bridge": "[bridge]",
        "outro": "[outro]",
        "pre-chorus": "[pre-chorus]",
        "prechorus": "[pre-chorus]",
        "hook": "[hook]",
        "interlude": "[inst]",
        "solo": "[inst]",
        "inst": "[inst]",
        "instrumental": "[inst]"
    ]

    /// Identifies if a bracketed line is a musical section header and returns its canonical form
    public static func canonicalSectionTag(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else { return nil }
        let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces).lowercased()
        for (kw, canonical) in standardSectionKeywords {
            if inner == kw || inner.hasPrefix(kw + " ") || inner.hasPrefix(kw + "-") {
                return canonical
            }
        }
        return nil
    }

    /// Automatically detects language of lyric text (CJK characters -> Chinese; otherwise English/Latin)
    public static func detectLanguage(text: String) -> String {
        for scalar in text.unicodeScalars {
            let val = scalar.value
            if (0x4E00...0x9FFF).contains(val) || (0x3400...0x4DBF).contains(val) || (0x20000...0x2A6DF).contains(val) {
                return "zh"
            }
        }
        return "en"
    }

    /// Extracts non-structural descriptive cues (e.g. [Slow piano start], [Soft and gentle]) from lyrics
    /// and canonicalizes musical section tags ([Verse 1] -> [verse])
    public static func extractDirectivesAndCleanLyrics(lyrics: String) -> (cleanedLyrics: String, extractedDirectives: [String]) {
        let lines = lyrics.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        var directives: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                cleanedLines.append("")
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if let canonical = canonicalSectionTag(from: trimmed) {
                    cleanedLines.append(canonical)
                } else {
                    let cue = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                    if !cue.isEmpty {
                        directives.append(cue)
                    }
                }
            } else {
                cleanedLines.append(trimmed)
            }
        }

        let cleaned = cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, directives)
    }

    /// Prepares enriched genre tags with language prefix and extracted directives.
    ///
    /// `modelLanguage` is the language the loaded Stage 1 checkpoint was trained on.
    /// YuE ships separate per-language models, and telling an English-only
    /// checkpoint to produce "Mandarin vocal" asks for something it cannot do, so
    /// the prefix is only added when the model actually matches the lyrics.
    public static func enrichGenreTags(
        genreTags: String,
        lyrics: String,
        extraDirectives: [String] = [],
        modelLanguage: String? = nil
    ) -> String {
        var tags = genreTags.trimmingCharacters(in: .whitespacesAndNewlines)
        let lang = detectLanguage(text: lyrics)
        let effective = (modelLanguage == nil || modelLanguage == lang) ? lang : (modelLanguage ?? lang)

        let lower = tags.lowercased()
        if effective == "zh" && !lower.contains("chinese") && !lower.contains("mandarin") && !lower.contains("cantonese") {
            tags = "Chinese, Mandarin vocal, " + tags
        } else if effective == "en" && !lower.contains("english") {
            tags = "English, " + tags
        }

        if !extraDirectives.isEmpty {
            let directiveStr = extraDirectives.joined(separator: ", ")
            tags = tags + ", " + directiveStr
        }

        return tags
    }

    /// Splits cleaned lyrics into distinct section segments based on canonical tags
    public static func splitIntoSegments(lyrics: String) -> [String] {
        let (cleaned, _) = extractDirectivesAndCleanLyrics(lyrics: lyrics)
        let lines = cleaned.components(separatedBy: .newlines)
        var sections: [String] = []
        var currentSection: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if canonicalSectionTag(from: trimmed) != nil {
                if !currentSection.isEmpty {
                    sections.append(currentSection.joined(separator: "\n"))
                }
                currentSection = [trimmed]
            } else {
                currentSection.append(trimmed)
            }
        }

        if !currentSection.isEmpty {
            sections.append(currentSection.joined(separator: "\n"))
        }

        if sections.isEmpty {
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? ["[verse]\n"] : ["[verse]\n" + trimmed]
        }

        return sections
    }

    /// Returns clean, ordered generation segments.
    /// Does NOT merge [intro] with [verse] so the model accurately respects section roles.
    public static func prepareOrderedSegments(lyrics: String) -> [String] {
        let segments = splitIntoSegments(lyrics: lyrics)
        guard !segments.isEmpty else { return ["[verse]\n"] }
        return segments
    }

    /// Formats the prompt for Segment 0 (header + full lyrics + first segment)
    /// Strictly matches official YuE Stage 1 format
    public static func formatSegment0Prompt(
        genreTags: String,
        lyrics: String,
        firstSegment: String,
        scoreABC: String? = nil,
        cotMode: String? = nil,
        referencePrompt: String? = nil,
        referenceMode: ReferenceMode? = nil,
        modelLanguage: String? = nil
    ) -> String {
        let (cleanedLyrics, directives) = extractDirectivesAndCleanLyrics(lyrics: lyrics)
        let enrichedGenres = enrichGenreTags(genreTags: genreTags, lyrics: cleanedLyrics,
                                             extraDirectives: directives, modelLanguage: modelLanguage)
        let segments = splitIntoSegments(lyrics: cleanedLyrics)
        let fullLyrics = segments.joined(separator: "\n\n")

        // YuE Stage 1 was trained on exactly three things: the instruction line, a
        // [Genre] line, and the lyrics. Anything else is out-of-distribution text
        // the model still has to attend to.
        //
        // This previously injected a "[System: YuE2 Music Symbolic Planner ...]"
        // marker on every generation, plus a "[Score Plan]:" block of ABC notation
        // in the score-driven modes. Neither token exists in YuE's training data,
        // and music-shaped ABC text sitting right before [start_of_segment] is
        // especially damaging to the melody. The symbolic plan still drives the
        // sheet-music view and score export; it just no longer contaminates the
        // model's conditioning. `cotMode` and `scoreABC` are kept in the signature
        // for the callers that pass them.
        _ = cotMode
        _ = scoreABC

        var lines: [String] = []
        lines.append("Generate music from the given lyrics segment by segment.")
        lines.append("\(genreHeader) \(enrichedGenres)")
        lines.append(fullLyrics)
        lines.append("")

        if let ref = referencePrompt, !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let modeTag = (referenceMode == .fullReference) ? "[Full Audio Reference]" : "[Melody Vocal Reference]"
            lines.append(modeTag)
            lines.append(startOfReference)
            lines.append(ref.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append(endOfReference)
            lines.append("")
        }

        lines.append(startOfSegment)
        lines.append(firstSegment)
        lines.append("")

        return lines.joined(separator: "\n")
    }

    /// Formats the transition prompt for subsequent segments (segment i > 0)
    public static func formatNextSegmentPrompt(segment: String) -> String {
        var lines: [String] = []
        lines.append(endOfSegment)
        lines.append(startOfSegment)
        lines.append(segment)
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Canonical full format method for single-pass / preview
    public static func format(
        genreTags: String,
        lyrics: String,
        scoreABC: String? = nil,
        cotMode: String? = nil,
        referencePrompt: String? = nil,
        referenceMode: ReferenceMode? = nil
    ) -> String {
        let segments = prepareOrderedSegments(lyrics: lyrics)
        let firstSegment = segments.first ?? "[verse]\n"
        return formatSegment0Prompt(
            genreTags: genreTags,
            lyrics: lyrics,
            firstSegment: firstSegment,
            scoreABC: scoreABC,
            cotMode: cotMode,
            referencePrompt: referencePrompt,
            referenceMode: referenceMode
        )
    }

    /// Extract section headers such as [verse], [chorus], [intro]
    public static func extractSections(from lyrics: String) -> [String] {
        let segments = splitIntoSegments(lyrics: lyrics)
        return segments.compactMap { seg in
            guard let firstLine = seg.components(separatedBy: .newlines).first else { return nil }
            guard let tag = canonicalSectionTag(from: firstLine) else { return nil }
            return String(tag.dropFirst().dropLast())
        }
    }
}

