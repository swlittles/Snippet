import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TemplateRequest: Identifiable {
    let id = UUID()
    var text: String
    var copyOnly: Bool
    var clipboard: String
    var formatted = false
    var queueID: UUID? = nil
}
struct TemplateView: View {
    let request: TemplateRequest
    let complete: (ExpandedTemplate, Bool) -> Void
    @State private var values: [String: String] = [:]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var shortcuts: ShortcutStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fill in your snippet").font(.title2.bold())
            ScrollView {
                ForEach(SnippetTemplate.fields(request.text), id: \.self) { field in
                    TextField(field, text: Binding(get: { values[field] ?? "" }, set: { values[field] = $0 })).textFieldStyle(.roundedBorder)
                }
            }.frame(maxHeight: 200)
            MarkdownPreview(text: SnippetTemplate.expand(request.text, values: values, clipboard: request.clipboard).text).frame(height: 160)
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(shortcuts[.cancelEditor].swiftUI); Spacer(); Button(request.copyOnly ? "Copy" : "Paste") {
                let result = SnippetTemplate.expand(request.text, values: values, clipboard: request.clipboard)
                dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { complete(result, request.formatted) }
            }.keyboardShortcut(shortcuts[.saveEditor].swiftUI).buttonStyle(.borderedProminent).pointerCursor() }
        }.padding(24).frame(width: 510).background(theme.background).foregroundStyle(theme.text).tint(theme.accent)
    }
}

struct WorkspaceView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var store: Store
    @ObservedObject var sync: LibrarySync
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var section = 0
    @State private var tool = TextTool.json
    @State private var input = ""
    @State private var output = ""
    @State private var notice = ""
    @State private var collection = ""
    @State private var linkTitle = ""
    @State private var destination = ""
    @State private var linkQuery = ""
    @State private var editingLink: UUID?
    @State private var separator = "\n"
    @State private var pack: SnippetPack?
    @State private var packTheme = false
    @State private var exportCollection = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Workspace").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Picker("Workspace", selection: $section) {
                Text("Tools").tag(0); Text("Queue (\(workspace.data.queue.count))").tag(1); Text("Quicklinks").tag(2); Text("Collections").tag(3); Text("Import / export").tag(4); Text("Sync").tag(5)
            }.pickerStyle(.segmented).labelsHidden()
            Group {
                switch section {
                case 1: queue
                case 2: quicklinks
                case 3: collections
                case 4: packs
                case 5: syncView
                default: tools
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(theme.accent).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            if let error = workspace.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(24).frame(width: 640, height: 540).foregroundStyle(theme.text).background(theme.background).tint(theme.accent)
            .preferredColorScheme(theme.palette.isDark ? .dark : .light)
            .buttonStyle(WorkspaceButtonStyle())
            .onAppear { input = model.current?.text ?? ""; section = model.workspaceSection }
            .onChange(of: section) { _ in notice = "" }
    }
    var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Action", selection: $tool) { ForEach(TextTool.allCases) { Text($0.rawValue).tag($0) } }
                Button("Run") { do { output = try tool.apply(input); notice = tool == .jwt ? "Decoded locally. The JWT signature has NOT been verified." : "" } catch { output = ""; notice = error.localizedDescription } }.buttonStyle(.borderedProminent).pointerCursor()
            }
            HStack {
                Button("Read clipboard") { input = NSPasteboard.general.string(forType: .string) ?? "" }
                Spacer(); Text("Everything runs on this Mac").font(.caption).foregroundStyle(theme.secondary)
            }
            CodeEditor(text: $input, label: "Tool input").font(.system(size: 12, design: .monospaced)).accessibilityLabel("Tool input").frame(height: 120)
            Text("RESULT").font(.caption)
            CodeEditor(text: $output, label: "Tool output").font(.system(size: 12, design: .monospaced)).accessibilityLabel("Tool output").frame(height: 120)
            HStack {
                Button("Use as input") { input = output }.disabled(output.isEmpty)
                Button("Save as snippet") { let item = SnippetItem(title: tool.rawValue, text: output, tags: "developer"); dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { model.editing = item } }.disabled(output.isEmpty)
                Spacer(); Button("Copy") { model.app.copyText(output); notice = "Copied" }.disabled(output.isEmpty)
                Button("Paste") { let value = output; dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { model.app.pasteText(value, copyOnly: false) } }.disabled(output.isEmpty)
            }
        }
    }
    var queue: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collect clips or snippets with “Add to queue”. Paste the next item when your destination is ready.").font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack {
                    ForEach(Array(workspace.data.queue.enumerated()), id: \.element.id) { index, entry in
                        HStack {
                            Text("\(index + 1)").foregroundStyle(theme.secondary)
                            Text(entry.title).lineLimit(1); Spacer()
                            Button { workspace.move(entry.id, offset: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Move up")
                            Button { workspace.move(entry.id, offset: 1) } label: { Image(systemName: "arrow.down") }.disabled(index == workspace.data.queue.count - 1).help("Move down")
                            Button { workspace.update { $0.queue.removeAll { $0.id == entry.id } } } label: { Image(systemName: "xmark") }.help("Remove from queue")
                        }.padding(8).background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }.frame(maxHeight: .infinity)
            if workspace.data.queue.isEmpty { Text("The paste queue is empty.").foregroundStyle(theme.secondary) }
            HStack {
                Picker("Join with", selection: $separator) { Text("Newlines").tag("\n"); Text("Blank lines").tag("\n\n"); Text("Spaces").tag(" "); Text("Tabs").tag("\t"); Text("Commas").tag(", ") }
                Button("Paste combined") {
                    let text = workspace.data.queue.map(\.text).joined(separator: separator)
                    dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { model.app.pasteText(text, copyOnly: false) }
                }.disabled(workspace.data.queue.isEmpty)
                Button("Copy combined text") { model.app.copyText(workspace.data.queue.map(\.text).joined(separator: separator)); notice = "Combined text copied. Image entries contribute their recognized text." }.disabled(workspace.data.queue.isEmpty)
            }
            HStack {
                Button("Clear queue") { workspace.update { $0.queue.removeAll() } }.disabled(workspace.data.queue.isEmpty)
                Spacer(); Button("Paste next") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { model.pasteNext() } }.buttonStyle(.borderedProminent).pointerCursor().disabled(workspace.data.queue.isEmpty)
            }
        }
    }
    var quicklinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search words for {query}", text: $linkQuery).textFieldStyle(.roundedBorder)
            ScrollView {
                ForEach(workspace.data.links.filter { linkQuery.isEmpty || $0.title.localizedStandardContains(linkQuery) || $0.destination.contains("{query}") }) { link in
                    HStack {
                        Button(link.title) {
                            do { let url = try link.destinationURL(query: linkQuery); dismiss(); model.app.hide(); NSWorkspace.shared.open(url) }
                            catch { notice = error.localizedDescription }
                        }.buttonStyle(WorkspaceButtonStyle())
                        Spacer()
                        Button("Edit") { editingLink = link.id; linkTitle = link.title; destination = link.destination }
                        Button("Delete") { workspace.update { $0.links.removeAll { $0.id == link.id } } }
                    }.padding(.vertical, 4)
                }
            }.frame(maxHeight: .infinity)
            Text(editingLink == nil ? "New quicklink" : "Edit quicklink").font(.headline)
            TextField("Name", text: $linkTitle).textFieldStyle(.roundedBorder)
            TextField("https://example.com/search?q={query} or /folder/path", text: $destination).textFieldStyle(.roundedBorder)
            HStack {
                Button("Choose folder…") {
                    let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
                    if panel.runModal() == .OK, let url = panel.url { destination = url.path; if linkTitle.isEmpty { linkTitle = url.lastPathComponent } }
                }
                Spacer()
                if editingLink != nil { Button("Cancel edit") { editingLink = nil; linkTitle = ""; destination = "" } }
                Button("Save quicklink") {
                    let link = Quicklink(id: editingLink ?? UUID(), title: linkTitle, destination: destination)
                    do { _ = try link.url(query: "test"); if workspace.update({ $0.links.removeAll { $0.id == link.id }; $0.links.append(link) }) { linkTitle = ""; destination = ""; editingLink = nil; notice = "Quicklink saved" } }
                    catch { notice = error.localizedDescription }
                }.disabled(linkTitle.trimmingCharacters(in: .whitespaces).isEmpty || destination.isEmpty)
            }
        }
    }
    var collections: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Group snippets by project or purpose. Assign a collection in the snippet editor and filter it in the launcher.").font(.caption).fixedSize(horizontal: false, vertical: true)
            HStack { TextField("New collection", text: $collection).textFieldStyle(.roundedBorder); Button("Create") {
                let name = collection.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { workspace.update { if !$0.collections.contains(name) { $0.collections.append(name) } }; collection = "" }
            }.disabled(collection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            ScrollView {
                ForEach(model.collections, id: \.self) { name in
                    HStack {
                        Text(name); Spacer(); Text("\(store.items.filter { $0.collection == name }.count)").foregroundStyle(theme.secondary)
                        Button("Show") { model.collectionFilter = name; model.switchTab(.snippets); dismiss() }
                        Button("Ungroup") {
                            var items = store.items
                            for index in items.indices where items[index].collection == name { items[index].collection = nil; items[index].updatedAt = Date() }
                            if store.replace(items) { workspace.update { $0.collections.removeAll { $0 == name } }; if model.collectionFilter == name { model.collectionFilter = "" } }
                        }
                    }.padding(.vertical, 6)
                }
            }
        }
    }
    var packs: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Share reusable snippet collections").font(.headline)
            Text("Import a Snippet pack, a previous snippets.json library, Markdown, or an Alfred collection (.alfredsnippets) or snippet JSON. Imports add copies and never overwrite your library. Keyword expansion starts off for imported snippets.").font(.caption).fixedSize(horizontal: false, vertical: true)
            Button("Choose import…") {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.json, .plainText, UTType(filenameExtension: "md") ?? .data, UTType(filenameExtension: "alfredsnippets") ?? .data]; panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url { do { pack = try SnippetPack.read(url); notice = "Review the import below." } catch { notice = error.localizedDescription } }
            }
            if let pack {
                Text("\(pack.snippets.count) snippets · \(pack.collections.count) collections · \(pack.quicklinks.count) quicklinks").font(.headline)
                ScrollView { ForEach(pack.snippets) { Text($0.title).frame(maxWidth: .infinity, alignment: .leading) } }.frame(maxHeight: 90)
                if pack.theme != nil { Toggle("Apply included theme", isOn: $packTheme) }
                HStack {
                    Button("Cancel") { self.pack = nil }
                    Button("Import copies") {
                        var items = store.items
                        for var item in pack.snippets { item.id = UUID(); item.updatedAt = Date(); item.expands = false; if items.contains(where: { $0.keyword == item.keyword }) { item.keyword = nil }; items.append(item) }
                        if store.replace(items) {
                            workspace.update { data in
                                data.collections = Array(Set(data.collections + pack.collections)).sorted()
                                for var link in pack.quicklinks { link.id = UUID(); link.updatedAt = Date(); data.links.append(link) }
                            }
                            if packTheme, let palette = pack.theme { theme.palette = palette }
                            notice = "Imported \(pack.snippets.count) snippets"; self.pack = nil
                        }
                    }.buttonStyle(.borderedProminent).pointerCursor()
                }
            }
            Divider()
            Picker("Export", selection: $exportCollection) { Text("All snippets").tag(""); ForEach(model.collections, id: \.self) { Text($0).tag($0) } }
            Text("Packs contain snippet text, quicklinks and your theme. Clipboard history, queue, preferences and signing credentials are excluded.").font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Export pack…") {
                let panel = NSSavePanel(); panel.nameFieldStringValue = "Snippet-pack.json"; panel.allowedContentTypes = [.json]
                if panel.runModal() == .OK, let url = panel.url {
                    do {
                        let items = store.items.filter { exportCollection.isEmpty || $0.collection == exportCollection }
                        let pack = SnippetPack(snippets: items, collections: exportCollection.isEmpty ? model.collections : [exportCollection], quicklinks: exportCollection.isEmpty ? workspace.data.links : [], theme: theme.palette)
                        try WorkspaceStore.write(pack, to: url); notice = "Pack exported"
                    } catch { notice = error.localizedDescription }
                }
            }
        }
    }
    var syncView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your library across Macs").font(.headline)
            Text("Choose the same dedicated iCloud Drive folder on each Mac. Snippets, collections, quicklinks and your theme sync every 30 seconds while Snippet runs. iCloud Drive handles transport; Apple may need time to download changes.").font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("The folder contains readable library data. Choose a private folder. The latest edit wins when the same item changes on two Macs; deletions sync too. Queue, hotkeys and retention preferences stay on this Mac.").font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Also sync clipboard history and images", isOn: $sync.shareClips)
            Text("Enable on each participating Mac. Turning this off stops future clipboard transfers; it does not erase copies already in the shared folder or on other Macs.").font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            if let folder = sync.folder { Text(folder.path).font(.caption).textSelection(.enabled) }
            Text(sync.status).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack { Button(sync.folder == nil ? "Choose iCloud Drive folder…" : "Change folder…") { sync.chooseFolder() }; if sync.folder != nil { Button("Sync now") { sync.sync() }; Button("Disconnect") { sync.disconnect() } } }
        }
    }
}

private struct WorkspaceButtonStyle: ButtonStyle {
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.isEnabled) var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 5)
            .background(theme.surface.opacity(configuration.isPressed ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 5))
            .opacity(enabled ? 1 : 0.4).contentShape(Rectangle()).pointerCursor()
    }
}
