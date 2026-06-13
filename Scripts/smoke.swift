#!/usr/bin/env swift
// Quick smoke test: parse all of ~/.claude/projects/ and print aggregates.
// Run with: swift Scripts/smoke.swift
import Foundation

let home = FileManager.default.homeDirectoryForCurrentUser
let root = home.appendingPathComponent(".claude/projects")
let fm = FileManager.default
guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
    fputs("no projects dir\n", stderr); exit(1)
}

struct Totals { var input=0, cacheW=0, cacheR=0, output=0, msgs=0 }
var byProject: [String: Totals] = [:]
var byModel:   [String: Totals] = [:]
var byDay:     [String: Totals] = [:]
var grand = Totals()
var files = 0

let iso = ISO8601DateFormatter()
iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let iso2 = ISO8601DateFormatter()
iso2.formatOptions = [.withInternetDateTime]
let dayFmt = DateFormatter()
dayFmt.dateFormat = "yyyy-MM-dd"

for case let url as URL in en where url.pathExtension == "jsonl" {
    files += 1
    let project = url.deletingLastPathComponent().lastPathComponent
    guard let txt = try? String(contentsOf: url, encoding: .utf8) else { continue }
    for line in txt.split(separator: "\n") {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any] else { continue }
        let i  = usage["input_tokens"] as? Int ?? 0
        let cw = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cr = usage["cache_read_input_tokens"] as? Int ?? 0
        let o  = usage["output_tokens"] as? Int ?? 0
        let model = msg["model"] as? String ?? "?"
        let ts = (obj["timestamp"] as? String).flatMap { iso.date(from: $0) ?? iso2.date(from: $0) } ?? Date()
        let day = dayFmt.string(from: ts)
        func add(_ t: inout Totals) { t.input+=i; t.cacheW+=cw; t.cacheR+=cr; t.output+=o; t.msgs+=1 }
        add(&grand)
        add(&byProject[project, default: Totals()])
        add(&byModel[model, default: Totals()])
        add(&byDay[day, default: Totals()])
    }
}

func fmt(_ n: Int) -> String {
    if n < 1_000 { return "\(n)" }
    if n < 1_000_000 { return String(format: "%.1fK", Double(n)/1_000) }
    if n < 1_000_000_000 { return String(format: "%.2fM", Double(n)/1_000_000) }
    return String(format: "%.2fB", Double(n)/1_000_000_000)
}
func line(_ k: String, _ t: Totals) {
    let tot = t.input + t.cacheW + t.cacheR + t.output
    let pad = k.padding(toLength: 50, withPad: " ", startingAt: 0)
    print("  \(pad)  \(fmt(tot)) total  (in \(fmt(t.input)), cW \(fmt(t.cacheW)), cR \(fmt(t.cacheR)), out \(fmt(t.output)), msgs \(t.msgs))")
}

print("files scanned: \(files)")
print("\nGRAND TOTAL")
line("all", grand)

print("\nBY MODEL")
for (k, v) in byModel.sorted(by: { ($0.value.input + $0.value.cacheW + $0.value.cacheR + $0.value.output) > ($1.value.input + $1.value.cacheW + $1.value.cacheR + $1.value.output) }) { line(k, v) }

print("\nBY DAY (last 10)")
for (k, v) in byDay.sorted(by: { $0.key > $1.key }).prefix(10) { line(k, v) }

print("\nBY PROJECT (top 8)")
for (k, v) in byProject.sorted(by: { ($0.value.input + $0.value.cacheW + $0.value.cacheR + $0.value.output) > ($1.value.input + $1.value.cacheW + $1.value.cacheR + $1.value.output) }).prefix(8) { line(k, v) }
