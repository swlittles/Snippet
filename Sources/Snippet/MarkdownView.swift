import SwiftUI
import AppKit

/// Native rendering: raw HTML is displayed as text; remote images are never fetched.
struct MarkdownPreview: View {
    var text: String
    var blocks: [MarkdownBlock] { MarkdownBlock.parse(text) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    if let rows = block.table {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, cells in
                                GridRow {
                                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                                        Text((try? AttributedString(markdown: cell)) ?? AttributedString(cell)).font(.system(size: 12, weight: rowIndex == 0 ? .semibold : .regular)).textSelection(.enabled)
                                    }
                                }
                            }
                        }.padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    } else if block.code {
                        Text(block.text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text((try? AttributedString(markdown: block.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(block.text))
                            .font(block.heading > 0 ? .system(size: CGFloat(25 - block.heading * 2), weight: .bold) : .system(size: 13))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }.accessibilityLabel("Markdown preview")
            .environment(\.openURL, OpenURLAction { url in
                guard ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
                return .systemAction
            })
    }
}
struct MarkdownBlock: Equatable {
    var text: String
    var code = false
    var heading = 0
    var table: [[String]]? = nil
    static func parse(_ source: String) -> [Self] {
        var blocks: [Self] = [], code: [String] = [], inCode = false
        for line in source.components(separatedBy: "\n") {
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if inCode { blocks.append(.init(text: code.joined(separator: "\n"), code: true)); code = [] }
                inCode.toggle(); continue
            }
            if inCode { code.append(line); continue }
            let level = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(level), line.dropFirst(level).hasPrefix(" ") { blocks.append(.init(text: String(line.dropFirst(level + 1)), heading: level)) }
            else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") { blocks.append(.init(text: "☑ " + line.dropFirst(6))) }
            else if line.hasPrefix("- [ ] ") { blocks.append(.init(text: "☐ " + line.dropFirst(6))) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") { blocks.append(.init(text: "• " + line.dropFirst(2))) }
            else if line.hasPrefix("> ") { blocks.append(.init(text: "▎ " + line.dropFirst(2))) }
            else if !line.isEmpty { blocks.append(.init(text: line)) }
        }
        if inCode { blocks.append(.init(text: code.joined(separator: "\n"), code: true)) }
        var result: [Self] = [], index = 0
        func cells(_ line: String) -> [String] { line.trimmingCharacters(in: CharacterSet(charactersIn: "| ")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
        while index < blocks.count {
            if index + 1 < blocks.count, !blocks[index].code, blocks[index].text.contains("|"), !blocks[index + 1].code,
               cells(blocks[index + 1].text).allSatisfy({ $0.contains("---") && $0.allSatisfy { "-: ".contains($0) } }) {
                var rows = [cells(blocks[index].text)]; index += 2
                while index < blocks.count && !blocks[index].code && blocks[index].text.contains("|") { rows.append(cells(blocks[index].text)); index += 1 }
                result.append(.init(text: rows.map { $0.joined(separator: "\t") }.joined(separator: "\n"), table: rows))
            } else { result.append(blocks[index]); index += 1 }
        }
        return result
    }
    static func attributed(_ text: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for block in parse(text) {
            let inline = block.code ? AttributedString(block.text) : (try? AttributedString(markdown: block.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(block.text)
            let paragraph = NSMutableAttributedString()
            for run in inline.runs {
                let intent = run.inlinePresentationIntent
                let mono = block.code || intent?.contains(.code) == true
                var font = mono ? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) : NSFont.systemFont(ofSize: block.heading > 0 ? CGFloat(25 - block.heading * 2) : 13)
                if block.heading > 0 || intent?.contains(.stronglyEmphasized) == true { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if intent?.contains(.emphasized) == true { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                var attributes: [NSAttributedString.Key: Any] = [.font: font]
                if intent?.contains(.strikethrough) == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if let link = run.link, ["https", "http", "mailto"].contains(link.scheme?.lowercased() ?? "") { attributes[.link] = link }
                paragraph.append(NSAttributedString(string: String(inline[run.range].characters), attributes: attributes))
            }
            output.append(paragraph); output.append(NSAttributedString(string: "\n"))
        }
        return output
    }
}
