import SwiftUI

struct DelimitedFormatMenu: View {
    @ObservedObject var document: LogDocument
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showCustomDelimiter = false
    @State private var customDelimiter = ""
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Button {
                apply(DelimitedLogOptions())
            } label: {
                Label("Automatic format", systemImage: document.delimitedOptions == DelimitedLogOptions()
                      ? "checkmark" : "circle")
            }
            Divider()
            ForEach(DelimitedLogOptions.automaticDelimiters + ["-"], id: \.self) { delimiter in
                Button {
                    var options = document.delimitedOptions
                    options.delimiter = String(delimiter)
                    apply(options)
                } label: {
                    Label(DelimitedLogOptions.delimiterName(delimiter),
                          systemImage: document.delimitedOptions.delimiter == String(delimiter)
                          ? "checkmark" : "circle")
                }
            }
            Button("Custom separator…") {
                customDelimiter = document.delimitedOptions.delimiter ?? ""
                showCustomDelimiter = true
            }
            Menu("First row") {
                ForEach(DelimitedLogOptions.HeaderMode.allCases, id: \.self) { mode in
                    Button {
                        var options = document.delimitedOptions
                        options.headerMode = mode
                        apply(options)
                    } label: {
                        Label(mode.title, systemImage: document.delimitedOptions.headerMode == mode
                              ? "checkmark" : "circle")
                    }
                }
            }
        } label: {
            Text("\(document.delimitedOptions == DelimitedLogOptions() ? "Auto" : "Manual"): \(document.formatName)")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 230)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
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
