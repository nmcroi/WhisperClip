import Foundation
let f = ISO8601DateFormatter()
let entries = (0..<1000).map { i in
    TranscriptEntry(id: "fixture-\(i)", text: "Synthetic", createdAt: f.string(from: Date(timeIntervalSince1970: 1789650000 - Double(i))), name: "", pinned: false, language: "nl", model: "fixture", source: "mic.ios", duration: 1, segments: [])
}
let start = ContinuousClock.now
let result = entries.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
print("Old redundant date sort, 1000 already ordered entries:", start.duration(to: .now))
let next = ContinuousClock.now
let retained = entries
print("Retain database order:", next.duration(to: .now))
precondition(result == retained)
