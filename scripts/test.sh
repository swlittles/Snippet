#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/Snippet/TextTools.swift Sources/Snippet/Workspace.swift Sources/Snippet/MarkdownView.swift Sources/Snippet/LibrarySync.swift Sources/Snippet/AppEnvironment.swift Sources/Snippet/Store.swift Sources/Snippet/History.swift Sources/Snippet/Services.swift Sources/Snippet/Calculator.swift Sources/Snippet/Theme.swift Sources/Snippet/Navigation.swift Sources/Snippet/Shortcuts.swift Tests/SnippetTests/StoreTests.swift -o .build/store-tests
.build/store-tests
