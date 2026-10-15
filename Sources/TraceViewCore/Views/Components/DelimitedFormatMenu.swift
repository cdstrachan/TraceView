import SwiftUI
import AppKit

struct DelimitedFormatMenu: View {
    @ObservedObject var document: LogDocument
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showCustomDelimiter = false
    @State private var customDelimiter = ""
    @State private var errorMessage: String?

    var body: some View {
        DelimitedFormatPopUp(
            title: "\(document.delimitedOptions == DelimitedLogOptions() ? "Auto" : "Manual"): \(document.formatName)",
            options: document.delimitedOptions,
            onSelect: { apply($0) },
            onCustomSeparator: {
                customDelimiter = document.delimitedOptions.delimiter ?? ""
                showCustomDelimiter = true
            }
        )
        .frame(maxWidth: 230)
        .padding(.horizontal, 8)
        .help("Choose the separator and header interpretation for this file. Changes are saved when the file is reopened.")
        .sheet(isPresented: $showCustomDelimiter) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Custom separator").font(.headline)
                Text("Enter one character. Quoted fields can contain the separator.")
                TextField("Separator", text: $customDelimiter)
                    .textFieldStyle(.roundedBorder)
                if let error = DelimitedLogOptions.validationError(for: customDelimiter) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(themeManager.current.errorText)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { showCustomDelimiter = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Apply") {
                        var options = document.delimitedOptions
                        options.delimiter = customDelimiter
                        if apply(options) { showCustomDelimiter = false }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(DelimitedLogOptions.validationError(for: customDelimiter) != nil)
                }
            }
            .padding(20)
            .frame(width: 380)
        }
        .alert("Cannot change file format", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @discardableResult
    private func apply(_ options: DelimitedLogOptions) -> Bool {
        do {
            try document.setDelimitedOptions(options)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

    }
}

struct DelimitedFormatPopUp: NSViewRepresentable {
    let title: String
    let options: DelimitedLogOptions
    let onSelect: (DelimitedLogOptions) -> Void
    let onCustomSeparator: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.font = .systemFont(ofSize: 11)
        button.cell?.lineBreakMode = .byTruncatingMiddle
        button.menu = context.coordinator.makeMenu()
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        button.isEnabled = isEnabled
        // Document statistics publish every second, including during menu tracking.
        // Keep the open menu and its submenu intact until tracking finishes.
        guard !context.coordinator.isTracking else { return }
        button.menu?.items.first?.title = title
        if let menu = button.menu {
            context.coordinator.updateCheckmarks(in: menu)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: min(proposal.width ?? 230, nsView.intrinsicContentSize.width), height: 22)
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: DelimitedFormatPopUp
        private(set) var isTracking = false

        init(parent: DelimitedFormatPopUp) {
            self.parent = parent
        }

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            menu.addItem(withTitle: parent.title, action: nil, keyEquivalent: "")
            menu.addItem(item("Automatic format", choice: .automatic))
            menu.addItem(.separator())
            for delimiter in DelimitedLogOptions.automaticDelimiters + ["-"] {
                menu.addItem(item(DelimitedLogOptions.delimiterName(delimiter), choice: .delimiter(delimiter)))
            }
            menu.addItem(item("Custom separator…", choice: .custom))

            let firstRow = NSMenuItem(title: "First row", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "First row")
            submenu.autoenablesItems = false
            for mode in DelimitedLogOptions.HeaderMode.allCases {
                submenu.addItem(item(mode.title, choice: .header(mode)))
            }
            firstRow.submenu = submenu
            menu.addItem(firstRow)
            updateCheckmarks(in: menu)
            return menu
        }

        private func item(_ title: String, choice: Choice) -> ChoiceItem {
            let item = ChoiceItem(title: title, choice: choice)
            item.target = self
            item.action = #selector(selectChoice(_:))
            return item
        }

        func updateCheckmarks(in menu: NSMenu) {
            for item in menu.items {
                if let choiceItem = item as? ChoiceItem {
                    let selected: Bool
                    switch choiceItem.choice {
                    case .automatic: selected = parent.options == DelimitedLogOptions()
                    case .delimiter(let delimiter): selected = parent.options.delimiter == String(delimiter)
                    case .header(let mode): selected = parent.options.headerMode == mode
                    case .custom: selected = false
                    }
                    item.state = selected ? .on : .off
                }
                if let submenu = item.submenu {
                    updateCheckmarks(in: submenu)
                }
            }
        }

        @objc private func selectChoice(_ sender: ChoiceItem) {
            var options = parent.options
            switch sender.choice {
            case .automatic: options = DelimitedLogOptions()
            case .delimiter(let delimiter): options.delimiter = String(delimiter)
            case .header(let mode): options.headerMode = mode
            case .custom:
                parent.onCustomSeparator()
                return
            }
            parent.onSelect(options)
        }

        func menuWillOpen(_ menu: NSMenu) {
            updateCheckmarks(in: menu)
            isTracking = true
        }

        func menuDidClose(_ menu: NSMenu) {
            isTracking = false
        }
    }

    enum Choice {
        case automatic
        case delimiter(Character)
        case header(DelimitedLogOptions.HeaderMode)
        case custom
    }

    final class ChoiceItem: NSMenuItem {
        let choice: Choice

        init(title: String, choice: Choice) {
            self.choice = choice
            super.init(title: title, action: nil, keyEquivalent: "")
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
