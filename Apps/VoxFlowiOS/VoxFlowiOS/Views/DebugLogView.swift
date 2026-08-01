// Adapted from DictusApp/Views/DebugLogView.swift (commit 7264b1d8).
// Reads the App Group persistent log so keyboard cold-start events remain inspectable.
import Shared
import SwiftUI
import UIKit

private struct ParsedLogEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let level: String
    let subsystem: String
    let eventName: String
    let params: String

    var levelColor: Color {
        switch level.trimmingCharacters(in: .whitespaces).lowercased() {
        case "error": return .red
        case "warning": return .orange
        case "info": return Color.dictusAccent
        case "debug": return .secondary
        default: return .primary
        }
    }

    var levelIcon: String {
        switch level.trimmingCharacters(in: .whitespaces).lowercased() {
        case "error": return "exclamationmark.triangle.fill"
        case "warning": return "exclamationmark.circle.fill"
        case "info": return "info.circle.fill"
        case "debug": return "circle.fill"
        default: return "circle"
        }
    }
}

struct DebugLogView: View {
    @State private var logContent = ""
    @State private var entries: [ParsedLogEntry] = []

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    L10n.t("debug_logs.empty"),
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(L10n.t("debug_logs.empty_hint"))
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(entries) { entry in
                                logRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .onAppear {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: entries.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
        }
        .background(Color.dictusBackground.ignoresSafeArea())
        .navigationTitle(L10n.t("debug_logs.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = logContent
                    } label: {
                        Label(L10n.t("debug_logs.copy"), systemImage: "doc.on.doc")
                    }

                    Button(role: .destructive) {
                        PersistentLog.clear()
                        reloadLogs()
                    } label: {
                        Label(L10n.t("debug_logs.clear"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            reloadLogs()
        }
        .refreshable {
            reloadLogs()
        }
    }

    private func logRow(_ entry: ParsedLogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: entry.levelIcon)
                .font(.caption2)
                .foregroundStyle(entry.levelColor)
                .frame(width: 14)

            Text(entry.timestamp)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("[\(entry.subsystem)]")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(entry.levelColor)

            Text(entry.params.isEmpty ? entry.eventName : "\(entry.eventName) \(entry.params)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = entries.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func reloadLogs() {
        logContent = PersistentLog.read()
        entries = parseEntries(from: logContent)
    }

    private func parseEntries(from content: String) -> [ParsedLogEntry] {
        content
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .compactMap(parseLine)
    }

    private func parseLine(_ line: String) -> ParsedLogEntry? {
        guard let bracketEnd = line.firstIndex(of: "]"), line.first == "[" else {
            return fallbackEntry(for: line)
        }

        let timestampFull = String(line[line.index(after: line.startIndex)..<bracketEnd])
        let timeOnly: String
        if let tIndex = timestampFull.firstIndex(of: "T") {
            timeOnly = String(timestampFull[timestampFull.index(after: tIndex)...].prefix(8))
        } else {
            timeOnly = String(timestampFull.suffix(8))
        }

        guard line.distance(from: bracketEnd, to: line.endIndex) > 2 else {
            return fallbackEntry(for: line)
        }
        let afterTimestamp = String(line[line.index(bracketEnd, offsetBy: 2)...])
        guard let subStart = afterTimestamp.firstIndex(of: "["),
              let subEnd = afterTimestamp.firstIndex(of: "]", after: subStart) else {
            return fallbackEntry(for: line)
        }

        let level = String(afterTimestamp[afterTimestamp.startIndex..<subStart])
            .trimmingCharacters(in: .whitespaces)
        let subsystem = String(afterTimestamp[afterTimestamp.index(after: subStart)..<subEnd])
        let restStart = afterTimestamp.index(subEnd, offsetBy: 2, limitedBy: afterTimestamp.endIndex) ?? afterTimestamp.endIndex
        let rest = String(afterTimestamp[restStart...])
        let parts = rest.split(separator: " ", maxSplits: 1)

        return ParsedLogEntry(
            timestamp: timeOnly,
            level: level,
            subsystem: subsystem,
            eventName: parts.isEmpty ? rest : String(parts[0]),
            params: parts.count > 1 ? String(parts[1]) : ""
        )
    }

    private func fallbackEntry(for line: String) -> ParsedLogEntry {
        ParsedLogEntry(
            timestamp: "--:--:--",
            level: "INFO",
            subsystem: "log",
            eventName: line,
            params: ""
        )
    }
}

private extension StringProtocol {
    func firstIndex(of element: Character, after index: Index) -> Index? {
        let searchRange = self.index(after: index)..<endIndex
        return self[searchRange].firstIndex(of: element)
    }
}

