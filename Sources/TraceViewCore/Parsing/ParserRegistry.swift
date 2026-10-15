import Foundation

final class ParserRegistry {
    static let shared = ParserRegistry()

    private let parsers: [any LogParser] = [
        IPSParser(),          // .ips crash reports (two-part JSON)
        DiagParser(),         // .diag diagnostic reports (Date/Time: header)
        SCCMLogParser(),
        UnifiedLogParser(),
        JSONLogParser(),
        CSVLogParser(),
        PlainTextParser()     // Fallback
    ]

    /// Pick the highest-confidence parser for the given sample lines.
    /// Callers read/decompress the file once themselves and pass a sample
    /// here, so gzipped files don't get decompressed twice during load.
    func detectParser(
        sampleLines: [String],
        delimitedOptions: DelimitedLogOptions? = nil
    ) -> any LogParser {
        if let delimiter = delimitedOptions?.delimiter?.first {
            return CSVLogParser(
                delimiter: delimiter, sampleLines: sampleLines,
                headerMode: delimitedOptions?.headerMode ?? .auto
            )
        }
        var bestParser: (any LogParser) = PlainTextParser()
        var bestScore: Double = 0

        let candidates = delimitedOptions == nil ? parsers : parsers.filter { !($0 is CSVLogParser) }
            + DelimitedLogOptions.automaticDelimiters.map {
                CSVLogParser(delimiter: $0, sampleLines: sampleLines,
                             headerMode: delimitedOptions?.headerMode ?? .auto)
            }
        for parser in candidates {
            let score: Double
            if delimitedOptions == nil, let csv = parser as? CSVLogParser {
                score = csv.canParseLegacy(sampleLines: sampleLines)
            } else {
                score = parser.canParse(sampleLines: sampleLines)
            }
            if score > bestScore {
                bestScore = score
                bestParser = parser
            }
        }

        return bestParser
    }
}
