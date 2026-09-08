import Foundation
import AppKit
import SwiftUI

func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
func XCTAssertNotNil<T>(_ value: T?) { precondition(value != nil) }
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs) }

@main
final class StoreTests {
    static func main() throws {
        let tests = StoreTests()
        try tests.setUpWithError()
        defer { try? tests.tearDownWithError() }
        tests.testSaveEditReloadDelete()
        tests.testSearchAcrossFieldsAndFavorites()
        try tests.testCorruptFileIsPreserved()
        try tests.testLegacyMigration()
        tests.testEnvironments()
        tests.testHistory()
        try tests.testUnlimitedAndCustomRetention()
        try tests.testFavoriteRetentionAndEditing()
        tests.testExpansion()
        tests.testClipboardCapture()
        try tests.testCalculator()
        try tests.testCalculationHistory()
        tests.testThemesAndNavigation()
        tests.testShortcuts()
        tests.testFocusedLauncherToggle()
        tests.testResultNavigation()
        try tests.testPowerTools()
        try tests.testWorkspaceAndPacks()
        try tests.testLibrarySync()
        try tests.testImagePersistence()
        print("Passed 20 test groups: persistence, search, corruption, migration, history, expansion, capture, calculator, calculation history, themes/navigation, configurable shortcuts, result cycling")
    }
    func testPowerTools() throws {
        XCTAssertEqual(SnippetTemplate.fields("Hi {{name}} {{date}} {{name}} {{project}} {{date:MMMM}} {{cursor}}"), ["name", "project"])
        let expanded = SnippetTemplate.expand("Hi {{name}}!{{cursor}} {{clipboard}}", values: ["name": "Ada"], clipboard: "👋")
        XCTAssertEqual(expanded, ExpandedTemplate(text: "Hi Ada! 👋", cursorMoves: 2))
        XCTAssertEqual(SnippetTemplate.expand("{{name}}", values: ["name": "{{cursor}}"]).text, "{{cursor}}")
        XCTAssertEqual(try TextTool.base64Decode.apply(TextTool.base64Encode.apply("Hello 🌍")), "Hello 🌍")
        XCTAssertEqual(try TextTool.unescape.apply(TextTool.escape.apply("a\n\"b")), "a\n\"b")
        XCTAssertEqual(try TextTool.deduplicate.apply("a\nb\na"), "a\nb")
        XCTAssertEqual(try TextTool.cleanURL.apply("https://example.com/?utm_source=test&q=a%26b&fbclid=x#end"), "https://example.com/?q=a%26b#end")
        XCTAssertEqual(try TextTool.sha256.apply("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try NaturalCalculator.evaluate("15% of 80")?.value, 12)
        XCTAssertEqual(try NaturalCalculator.evaluate("2 gib to mib")?.value, 2048)
        XCTAssertEqual(try NaturalCalculator.evaluate("32 f to c")?.value, 0)
        XCTAssertEqual(try NaturalCalculator.evaluate("2024-02-28 + 1 day")?.display, "2024-02-29")
        XCTAssertEqual(try NaturalCalculator.evaluate("2024-03-01 - 1 day")?.display, "2024-02-29")
        do { _ = try NaturalCalculator.evaluate("10 kg to km"); preconditionFailure("Accepted incompatible units") } catch {}
        do { _ = try TextTool.json.apply("{bad}"); preconditionFailure("Accepted invalid JSON") } catch {}
        XCTAssertEqual(MarkdownBlock.parse("# Heading\n```swift\nlet x = 1\n```\n- [x] Done").count, 3)
        XCTAssertTrue(MarkdownBlock.parse("```\n**literal**").first!.code)
        XCTAssertEqual(MarkdownBlock.parse("| Name | Value |\n| --- | --- |\n| A | B |").first?.table, [["Name", "Value"], ["A", "B"]])
        let bold = MarkdownBlock.attributed("**Bold**")
        let font = bold.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }
    func testWorkspaceAndPacks() throws {
        let url = directory.appendingPathComponent("workspace.json"), workspace = WorkspaceStore(url: url)
        workspace.update { $0.collections = ["Work"]; $0.queue = [.init(title: "First", text: "1"), .init(title: "Second", text: "2")] }
        workspace.move(workspace.data.queue[0].id, offset: 1)
        XCTAssertEqual(WorkspaceStore(url: url).data.queue.map(\.text), ["2", "1"])
        let link = Quicklink(title: "Search", destination: "https://example.com/?q={query}")
        XCTAssertEqual(try link.url(query: "a&b #c").absoluteString, "https://example.com/?q=a%26b%20%23c")
        do { _ = try Quicklink(title: "Bad", destination: "javascript:alert(1)").url(query: ""); preconditionFailure("Accepted executable scheme") } catch {}
        let script = directory.appendingPathComponent("unsafe.command")
        try Data("echo example".utf8).write(to: script)
        do { _ = try Quicklink(title: "Not a folder", destination: script.path).destinationURL(query: ""); preconditionFailure("Accepted a script as a folder") } catch {}
        XCTAssertEqual(try Quicklink(title: "Folder", destination: directory.path).destinationURL(query: "").path, directory.path)
        let pack = SnippetPack(snippets: [.init(title: "Markdown", text: "# Hi", tags: "", collection: "Work", format: "markdown")], collections: ["Work"], quicklinks: [link])
        let packURL = directory.appendingPathComponent("pack.json"); try WorkspaceStore.write(pack, to: packURL)
        let loaded = try SnippetPack.read(packURL)
        XCTAssertEqual(loaded.snippets, pack.snippets)
        let alfred = directory.appendingPathComponent("alfred.json")
        try Data(#"{"alfredsnippet":{"name":"Reply","snippet":"Hello","keyword":";hello"}}"#.utf8).write(to: alfred)
        XCTAssertEqual(try SnippetPack.read(alfred).snippets.first?.expands, false)
    }
    func testLibrarySync() throws {
        let shared = directory.appendingPathComponent("shared"); try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        func client(_ name: String) -> LibrarySync {
            let root = directory.appendingPathComponent(name)
            let defaults = UserDefaults(suiteName: "test.snippet.sync." + name + UUID().uuidString)!
            return LibrarySync(store: Store(url: root.appendingPathComponent("snippets.json")), history: History(url: root.appendingPathComponent("history.json"), retention: { .init() }), workspace: WorkspaceStore(url: root.appendingPathComponent("workspace.json")), theme: ThemeStore(defaults: defaults), defaults: defaults, journalURL: root.appendingPathComponent("journal.json"), automatic: false)
        }
        let a = client("a"), b = client("b")
        let item = SnippetItem(title: "Synced", text: "original", tags: "", favorite: true, collection: "Work", format: "markdown")
        a.store.save(item); a.history.record("private clipboard", source: "Test")
        a.theme.palette = ThemePalette.presets[2]
        a.workspace.update { $0.collections = ["Work"] }; b.workspace.update { $0.collections = ["Personal"] }
        a.connect(shared); b.connect(shared)
        XCTAssertEqual(b.theme.palette, ThemePalette.presets[2])
        XCTAssertEqual(b.workspace.data.collections, ["Personal", "Work"])
        XCTAssertEqual(b.store.items.first?.text, "original")
        XCTAssertTrue(b.history.clips.isEmpty)
        var changed = b.store.items[0]; changed.text = "edited offline"; b.store.save(changed); b.sync(); a.sync()
        XCTAssertEqual(a.store.items.first?.text, "edited offline")
        b.store.delete(b.store.items[0]); b.sync(); a.sync()
        XCTAssertTrue(a.store.items.isEmpty)
        a.sync(); b.sync(); XCTAssertTrue(b.store.items.isEmpty)
        a.shareClips = true; b.shareClips = true; a.sync(); b.sync()
        XCTAssertEqual(b.history.clips.first?.text, "private clipboard")
        // Corrupt shared data must never be replaced by a fresh empty document.
        let remote = shared.appendingPathComponent("Snippet.sync.json")
        let bad = Data("broken".utf8); try bad.write(to: remote)
        a.sync(); XCTAssertEqual(try Data(contentsOf: remote), bad)
        XCTAssertTrue(a.status.hasPrefix("Sync paused:"))
    }
    func testImagePersistence() throws {
        let history = History(url: directory.appendingPathComponent("images/history.json"), retention: { .init(days: 1, limit: 1) })
        let image = Clip(text: "", source: "Screenshot", date: Date(), imageName: UUID().uuidString + ".png")
        XCTAssertTrue(history.appendImage(image)); history.toggleFavorite(image.id)
        XCTAssertTrue(history.clips[0].favorite)
        history.setRecognizedText("Searchable screenshot", id: image.id)
        XCTAssertEqual(history.search("searchable").first?.id, image.id)
        XCTAssertEqual(History(url: history.url).clips.first?.imageName, image.imageName)
        let invalid = Clip(text: "", source: "Test", date: Date(), imageName: "../../secret.png")
        XCTAssertEqual(history.imageURL(invalid), nil)
        let rendered = NSImage(size: NSSize(width: 600, height: 100))
        rendered.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 600, height: 100).fill()
        ("Snippet OCR 42" as NSString).draw(at: NSPoint(x: 20, y: 30), withAttributes: [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black])
        rendered.unlockFocus()
        history.recordImage(rendered, source: "OCR test")
        let captured = history.clips.first { $0.source == "OCR test" }!
        XCTAssertTrue(FileManager.default.fileExists(atPath: history.imageURL(captured)!.path))
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline && history.clips.first(where: { $0.id == captured.id })?.text.isEmpty == true { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertTrue(history.clips.first(where: { $0.id == captured.id })?.text.contains("Snippet OCR 42") == true)
        history.remove(captured.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.imageURL(captured)!.path))
    }
    var directory: URL!
    func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func testSaveEditReloadDelete() {
        let url = directory.appendingPathComponent("snippets.json")
        let store = Store(url: url)
        var item = SnippetItem(title: "Reply", text: "Hello\n世界 👋", tags: "work")
        XCTAssertTrue(store.save(item))
        item.title = "Updated reply"
        XCTAssertTrue(store.save(item))
        let reloaded = Store(url: url)
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.items.first?.title, "Updated reply")
        XCTAssertEqual(reloaded.items.first?.text, "Hello\n世界 👋")
        XCTAssertTrue(reloaded.delete(item))
        XCTAssertTrue(Store(url: url).items.isEmpty)
    }
    func testSearchAcrossFieldsAndFavorites() {
        let store = Store(url: directory.appendingPathComponent("snippets.json"))
        let a = SnippetItem(title: "Café reply", text: "Thanks for reaching out", tags: "work", favorite: true)
        let b = SnippetItem(title: "Address", text: "42 Main Street", tags: "personal")
        store.save(a); store.save(b)
        XCTAssertEqual(store.results("CAFE work").map(\.id), [a.id])
        XCTAssertEqual(store.results("main").map(\.id), [b.id])
        XCTAssertEqual(store.results("", favorites: true).map(\.id), [a.id])
        XCTAssertEqual(store.results("").first?.id, a.id)
        XCTAssertTrue(store.results("unmatched").isEmpty)
    }
    func testCorruptFileIsPreserved() throws {
        let url = directory.appendingPathComponent("snippets.json")
        let original = Data("broken json".utf8)
        try original.write(to: url)
        let store = Store(url: url)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.save(SnippetItem(title: "Test", text: "Test", tags: "")))
        let preserved = try Data(contentsOf: url)
        XCTAssertEqual(preserved, original)
    }
    func testLegacyMigration() throws {
        let url = directory.appendingPathComponent("legacy.json")
        let id = UUID()
        let json = "[{\"id\":\"\(id.uuidString)\",\"title\":\"Old\",\"text\":\"Keep me\",\"tags\":\"\",\"favorite\":false,\"updatedAt\":0}]"
        try Data(json.utf8).write(to: url)
        let store = Store(url: url)
        XCTAssertEqual(store.items.first?.id, id)
        XCTAssertEqual(store.items.first?.keyword, nil)
        XCTAssertEqual(store.items.first?.text, "Keep me")
    }
    func testEnvironments() {
        let production = AppEnvironment(bundleIdentifier: "local.snippet.app")
        let development = AppEnvironment(bundleIdentifier: "local.snippet.dev")
        XCTAssertFalse(production.isDevelopment)
        XCTAssertTrue(development.isDevelopment)
        XCTAssertEqual(AppEnvironment(bundleIdentifier: nil), development)
        XCTAssertEqual(production.name, "Snippet")
        XCTAssertEqual(development.name, "Snippet Dev")
        XCTAssertTrue(production.bundleIdentifier != development.bundleIdentifier)
        for filename in ["snippets.json", "history.json", "calculations.json"] {
            XCTAssertEqual(production.dataURL(filename, root: directory), directory.appendingPathComponent("Snippet/" + filename))
            XCTAssertEqual(development.dataURL(filename, root: directory), directory.appendingPathComponent("Snippet Dev/" + filename))
        }
    }
    func testUnlimitedAndCustomRetention() throws {
        let now = Date()
        let clips = (0..<1200).map { Clip(text: "item \($0)", source: "Test", date: now.addingTimeInterval(-Double($0) * 86400)) }
        let url = directory.appendingPathComponent("unlimited.json")
        try JSONEncoder().encode(clips).write(to: url)
        var policy = HistoryRetention()
        let history = History(url: url, retention: { policy })
        history.prune(now: now)
        XCTAssertEqual(history.clips.count, 1200)
        history.record("new item", source: "Test", now: now)
        XCTAssertEqual(history.clips.count, 1201)
        XCTAssertEqual(History(url: url, retention: { HistoryRetention() }).clips.count, 1201)
        let oldest = clips.last!
        history.toggleFavorite(oldest.id)
        policy = HistoryRetention(days: 30, limit: 10)
        history.prune(now: now)
        XCTAssertEqual(history.clips.count, 11)
        XCTAssertTrue(history.clips.contains { $0.id == oldest.id && $0.favorite })
        XCTAssertTrue(history.clips.contains { $0.text == "new item" })
        XCTAssertEqual(HistoryRetention(days: 7).retaining(clips, now: now).count, 7)
        XCTAssertEqual(HistoryRetention(limit: 1000).retaining(clips.reversed(), now: now).first?.id, clips.first?.id)
        XCTAssertEqual(HistoryRetention(limit: 1000).retaining(clips, now: now).count, 1000)
        XCTAssertEqual(HistoryRetention().retaining(clips, now: now.addingTimeInterval(4000 * 86400)), clips)
    }
    func testHistory() {
        let url = directory.appendingPathComponent("history.json")
        let history = History(url: url, retention: { HistoryRetention(days: 7, limit: 500) })
        let now = Date()
        history.record("older", source: "Test", now: now.addingTimeInterval(-8 * 86400))
        history.record("Hello 世界", source: "Editor", now: now)
        history.record("Second", source: "Browser", now: now)
        history.record("Hello 世界", source: "Editor", now: now)
        XCTAssertEqual(history.clips.count, 2)
        XCTAssertEqual(history.clips.first?.text, "Hello 世界")
        XCTAssertEqual(history.search("hello editor").count, 1)
        history.record(String(repeating: "x", count: 100001), source: "Test")
        XCTAssertEqual(history.clips.count, 2)
        XCTAssertEqual(History(url: url, retention: { HistoryRetention(days: 7, limit: 500) }).clips.count, 2)
        history.prune(now: now.addingTimeInterval(8 * 86400))
        XCTAssertTrue(history.clips.isEmpty)
    }
    func testFavoriteRetentionAndEditing() throws {
        let url = directory.appendingPathComponent("favorites.json")
        let now = Date()
        let old = now.addingTimeInterval(-9 * 86400)
        let legacy = Clip(text: "legacy", source: "Original", date: old)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode([legacy])) as! [[String: Any]]
        json[0].removeValue(forKey: "favorite")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let history = History(url: url, retention: { HistoryRetention(days: 7, limit: 500) })
        XCTAssertEqual(history.clips.first?.favorite, false)
        history.toggleFavorite(legacy.id)
        history.prune(now: now)
        XCTAssertEqual(history.clips.count, 1)
        for index in 0..<505 { history.record("clip \(index)", source: "Test", now: now) }
        XCTAssertEqual(history.clips.count, 501)
        XCTAssertEqual(history.search("", favorites: true).map(\.id), [legacy.id])
        history.record("legacy", source: "Recopied", now: now)
        XCTAssertEqual(history.clips.first?.id, legacy.id)
        XCTAssertEqual(history.clips.first?.favorite, true)
        var edited = history.clips.first!
        edited.text = "Updated 世界\nSecond line"
        XCTAssertTrue(history.update(edited))
        let reloaded = History(url: url, retention: { HistoryRetention(days: 7, limit: 500) })
        XCTAssertEqual(reloaded.clips.first?.text, edited.text)
        XCTAssertEqual(reloaded.clips.first?.id, legacy.id)
        XCTAssertEqual(reloaded.clips.first?.source, "Recopied")
        XCTAssertEqual(reloaded.clips.first?.date, now)
        XCTAssertEqual(reloaded.search("Updated", favorites: true).count, 1)
        edited.text = "   "
        XCTAssertFalse(reloaded.update(edited))
        reloaded.clear()
        XCTAssertEqual(reloaded.clips.count, 1)
        reloaded.prune(now: now.addingTimeInterval(30 * 86400))
        XCTAssertEqual(reloaded.clips.count, 1)
        reloaded.toggleFavorite(legacy.id)
        reloaded.prune(now: now.addingTimeInterval(30 * 86400))
        XCTAssertTrue(reloaded.clips.isEmpty)
    }
    func testExpansion() {
        let item = SnippetItem(title: "Email", text: "hello@example.com", tags: "", keyword: ";email", expands: true)
        var matcher = ExpansionMatcher()
        var match: SnippetItem?
        for character in ";email" { match = matcher.feed(String(character), snippets: [item]) }
        XCTAssertEqual(match?.id, item.id)
        XCTAssertEqual(matcher.buffer, "")
        for character in "word;email" { match = matcher.feed(String(character), snippets: [item]) }
        XCTAssertEqual(match, nil)
        matcher.reset()
        var disabled = item; disabled.expands = false
        for character in ";email" { match = matcher.feed(String(character), snippets: [disabled]) }
        XCTAssertEqual(match, nil)
        XCTAssertFalse(ExpansionMatcher.valid("email"))
        XCTAssertFalse(ExpansionMatcher.valid(";a b"))
        XCTAssertTrue(ExpansionMatcher.valid(";reply"))
    }
    func testClipboardCapture() {
        let board = NSPasteboard(name: NSPasteboard.Name("SnippetTest-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        let history = History(url: directory.appendingPathComponent("capture.json"))
        var enabled = true
        let service = ClipboardService(history: history, board: board, enabled: { enabled })
        board.clearContents(); board.setString("copied text", forType: .string)
        service.poll()
        XCTAssertEqual(history.clips.first?.text, "copied text")
        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"] {
            board.clearContents(); board.setString("private", forType: .string)
            board.setData(Data(), forType: NSPasteboard.PasteboardType(marker))
            service.poll()
        }
        XCTAssertEqual(history.clips.count, 1)
        enabled = false
        board.clearContents(); board.setString("paused", forType: .string)
        service.poll()
        enabled = true; service.poll()
        XCTAssertEqual(history.clips.count, 1)
    }
    func testCalculator() throws {
        let examples: [(String, Double)] = [
            ("2+3*4",14), ("(2+3)*4",20), ("-2^2",-4), ("2^-2",0.25), ("2^3^2",512),
            ("50%",0.5), ("200*15%",30), ("5!",120), ("0!",1), ("sqrt(81)",9),
            ("abs(-8)",8), ("log(100)",2), ("ln(e)",1), ("sin(pi/2)",1),
            ("min(3,4)+max(5,9)",12), ("pow(2,5)",32), ("2(3+4)",14),
            ("1.5e3+2.5",1502.5), ("3×4÷2",6), ("round(2.6)+floor(2.9)+ceil(2.1)",8)
        ]
        for (expression, expected) in examples {
            let value = try Calculator.evaluate(expression)
            precondition(abs(value-expected) < 1e-10, "Failed: " + expression)
        }
        let degrees = try Calculator.evaluate("sin(90)", degrees: true)
        precondition(abs(degrees-1) < 1e-10)
        XCTAssertEqual(try Calculator.evaluate("ans+7", answer: 5), 12)
        for invalid in ["1/0", "sqrt(-1)", "log(0)", "1.2.3", "2+", "(2+3", "unknown(2)", "min(1)", "171!", "1e309", "2**3", "", String(repeating: "(", count: 45) + "2" + String(repeating: ")", count: 45)] {
            do { _ = try Calculator.evaluate(invalid); preconditionFailure("Should reject: " + invalid) }
            catch { /* expected */ }
        }
        XCTAssertEqual(Calculator.format(-0), "0")
        XCTAssertEqual(Calculator.format(0.1 + 0.2), "0.3")
    }
    func testCalculationHistory() throws {
        let url = directory.appendingPathComponent("calculations.json")
        let store = CalculatorStore(url: url)
        XCTAssertTrue(store.record(expression: "2+2", result: 4, degrees: false))
        XCTAssertTrue(store.record(expression: "2+2", result: 4, degrees: false))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertTrue(store.record(expression: "sin(90)", result: 1, degrees: true))
        let reloaded = CalculatorStore(url: url)
        XCTAssertEqual(reloaded.entries.count, 2)
        XCTAssertEqual(reloaded.entries.first?.degrees, true)
        XCTAssertEqual(reloaded.answer, 1)
        reloaded.clear()
        XCTAssertTrue(CalculatorStore(url: url).entries.isEmpty)
        let bad = directory.appendingPathComponent("bad-calc.json")
        let bytes = Data("broken".utf8); try bytes.write(to: bad)
        let corrupt = CalculatorStore(url: bad)
        XCTAssertFalse(corrupt.record(expression: "2", result: 2, degrees: false))
        XCTAssertEqual(try Data(contentsOf: bad), bytes)
    }
    func testThemesAndNavigation() {
        let name = "SnippetTest-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let themes = ThemeStore(defaults: defaults)
        themes.palette = ThemePalette.presets[1]
        XCTAssertEqual(ThemeStore(defaults: defaults).palette.name, "Paper")
        XCTAssertFalse(themes.palette.isDark)
        themes.color(\.accent).wrappedValue = Color(hex: 0x123456)
        XCTAssertEqual(themes.palette.accent, 0x123456)
        XCTAssertEqual(ThemeStore(defaults: defaults).palette.name, "Custom")
        XCTAssertEqual(LauncherTab.command("1"), .history)
        XCTAssertEqual(LauncherTab.command("2"), .snippets)
        XCTAssertEqual(LauncherTab.command("3"), .calculator)
        XCTAssertEqual(LauncherTab.command("9"), nil)
        XCTAssertEqual(LauncherTab.history.cycled(backward: true), .calculator)
        XCTAssertEqual(LauncherTab.calculator.cycled(), .history)
    }
    func testShortcuts() {
        let name = "SnippetShortcutsTest-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let shortcuts = ShortcutStore(defaults: defaults)
        func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: KeyBinding.characters[code] ?? "", charactersIgnoringModifiers: KeyBinding.characters[code] ?? "", isARepeat: false, keyCode: code)!
        }
        for action in ShortcutAction.allCases { XCTAssertEqual(shortcuts.validation(action.standard, for: action), nil) }
        XCTAssertEqual(shortcuts.match(event(48), in: .launcher), .nextResult)
        XCTAssertEqual(shortcuts.match(event(48, .shift), in: .launcher), .previousResult)
        XCTAssertEqual(shortcuts.match(event(48), in: .calculator), nil)
        XCTAssertEqual(shortcuts.match(event(36), in: .calculator), .calculate)
        XCTAssertEqual(shortcuts.match(event(36), in: .launcher), .pasteResult)
        XCTAssertEqual(shortcuts.match(event(1, .command), in: .editor), .saveEditor)
        XCTAssertFalse(shortcuts.set(shortcuts[.clipboard], for: .snippets))
        XCTAssertNotNil(shortcuts.error)
        XCTAssertTrue(shortcuts.set(KeyBinding(19, [.command,.shift]), for: .snippets))
        XCTAssertEqual(shortcuts.match(event(19, [.command,.shift]), in: .launcher), .snippets)
        XCTAssertEqual(shortcuts.match(event(19, .command), in: .launcher), nil)
        XCTAssertEqual(ShortcutStore(defaults: defaults)[.snippets], shortcuts[.snippets])
        XCTAssertTrue(shortcuts.set(.disabled, for: .snippets))
        XCTAssertEqual(shortcuts.match(event(19, [.command,.shift]), in: .launcher), nil)
        let original = shortcuts[.toggle]
        shortcuts.registerGlobal = { _ in "Shortcut in use" }
        XCTAssertFalse(shortcuts.set(KeyBinding(49, [.command,.shift]), for: .toggle))
        XCTAssertEqual(shortcuts[.toggle], original)
        XCTAssertFalse(shortcuts.set(KeyBinding(49), for: .toggle))
        shortcuts.registerGlobal = { _ in nil }
        shortcuts.resetAll()
        XCTAssertEqual(shortcuts[.snippets], ShortcutAction.snippets.standard)
        shortcuts.recording = .snippets
        XCTAssertTrue(shortcuts.capture(event(53)))
        XCTAssertEqual(shortcuts.recording, nil)
    }
    func testFocusedLauncherToggle() {
        let name = "SnippetToggleTest-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let shortcuts = ShortcutStore(defaults: defaults)
        func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags, text: String = " ", repeated: Bool = false, type: NSEvent.EventType = .keyDown) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: repeated, keyCode: code)!
        }
        var toggles = 0
        func consume(_ event: NSEvent, visible: Bool = true) -> Bool {
            shortcuts.consumeLauncherToggle(event, launcherVisible: visible) { toggles += 1 }
        }
        XCTAssertTrue(shortcuts.set(KeyBinding(49, .option), for: .toggle))
        // Option-Space can arrive as a non-breaking space from the field editor.
        XCTAssertTrue(consume(event(49, .option, text: "\u{00a0}")))
        XCTAssertEqual(toggles, 1)
        XCTAssertTrue(consume(event(49, .option, repeated: true)))
        XCTAssertEqual(toggles, 1)
        XCTAssertFalse(consume(event(49, [])))
        // A second delivery (Carbon or AppKit) must not reopen the launcher.
        shortcuts.performTogglePress { toggles += 1 }
        XCTAssertTrue(consume(event(49, .option), visible: false))
        XCTAssertEqual(toggles, 1)
        XCTAssertTrue(shortcuts.consumeToggleRelease(event(49, [], type: .keyUp)))
        XCTAssertFalse(shortcuts.consumeToggleRelease(event(49, [], type: .keyUp)))
        XCTAssertFalse(consume(event(49, .option), visible: false))
        XCTAssertTrue(shortcuts.set(KeyBinding(40, [.control, .option]), for: .toggle))
        XCTAssertFalse(consume(event(49, .option)))
        XCTAssertTrue(consume(event(40, [.control, .option], text: "˚")))
        XCTAssertEqual(toggles, 2)
        shortcuts.releaseToggle()
        shortcuts.recording = .toggle
        XCTAssertFalse(consume(event(40, [.control, .option])))
        shortcuts.recording = nil
        XCTAssertTrue(shortcuts.set(.disabled, for: .toggle))
        XCTAssertFalse(consume(event(40, [.control, .option])))
    }
    func testResultNavigation() {
        XCTAssertEqual(ResultNavigation.index(current: 0, count: 3, backward: false, wraps: true), 1)
        XCTAssertEqual(ResultNavigation.index(current: 2, count: 3, backward: false, wraps: true), 0)
        XCTAssertEqual(ResultNavigation.index(current: 0, count: 3, backward: true, wraps: true), 2)
        XCTAssertEqual(ResultNavigation.index(current: 0, count: 3, backward: true, wraps: false), 0)
        XCTAssertEqual(ResultNavigation.index(current: nil, count: 0, backward: false, wraps: true), 0)
        XCTAssertEqual(ResultNavigation.index(current: 0, count: 1, backward: false, wraps: true), 0)
    }
}
