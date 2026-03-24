import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            // Appearance section
            VStack(alignment: .leading, spacing: 12) {
                Text("APPEARANCE")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle("Centered popup window", isOn: $settings.usePopupMode)
                        .toggleStyle(.checkbox)
                    
                    Text("Opens as a centered window instead of dropping from the menu bar. Takes effect on next toggle.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Divider()
                
                // Behavior section
                VStack(alignment: .leading, spacing: 12) {
                    Text("BEHAVIOR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle("Copy on single click", isOn: $settings.copyOnClick)
                        .toggleStyle(.checkbox)
                    
                    Toggle("Capture screenshots", isOn: $settings.captureScreenshots)
                        .toggleStyle(.checkbox)
                    
                    Toggle("Open URLs in browser on click", isOn: $settings.openURLsInBrowser)
                        .toggleStyle(.checkbox)
                    
                    Toggle("Syntax highlighting for code", isOn: $settings.syntaxHighlighting)
                        .toggleStyle(.checkbox)
                }
                
                Divider()
                
                // Keyboard Shortcuts section
                VStack(alignment: .leading, spacing: 12) {
                    Text("KEYBOARD SHORTCUTS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle("Enable keyboard mode", isOn: $settings.keyboardModeEnabled)
                        .toggleStyle(.checkbox)
                    
                    Text("When enabled, a global hotkey toggles the Pasteboard panel from anywhere.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    ShortcutRecorderRow(
                        label: "Toggle Pasteboard",
                        displayString: $settings.toggleHotkeyDisplay,
                        isGlobalHotkey: true,
                        onRecord: { keyCode, modifiers in
                            settings.toggleHotkeyKeyCode = UInt32(keyCode)
                            settings.toggleHotkeyModifiers = AppSettings.carbonModifiers(from: modifiers)
                            settings.toggleHotkeyDisplay = AppSettings.displayString(for: keyCode, modifiers: modifiers)
                        }
                    )
                    .disabled(!settings.keyboardModeEnabled)
                    .opacity(settings.keyboardModeEnabled ? 1 : 0.5)
                    
                    Toggle("Enable stack mode hotkey", isOn: $settings.stackModeHotkeyEnabled)
                        .toggleStyle(.checkbox)
                        .padding(.top, 4)
                    
                    ShortcutRecorderRow(
                        label: "Toggle Stack Mode",
                        displayString: $settings.stackModeHotkeyDisplay,
                        isGlobalHotkey: true,
                        onRecord: { keyCode, modifiers in
                            settings.stackModeHotkeyKeyCode = UInt32(keyCode)
                            settings.stackModeHotkeyModifiers = AppSettings.carbonModifiers(from: modifiers)
                            settings.stackModeHotkeyDisplay = AppSettings.displayString(for: keyCode, modifiers: modifiers)
                        }
                    )
                    .disabled(!settings.stackModeHotkeyEnabled)
                    .opacity(settings.stackModeHotkeyEnabled ? 1 : 0.5)
                    
                    ShortcutRecorderRow(
                        label: "Navigate Up",
                        displayString: $settings.navUpDisplay,
                        isGlobalHotkey: false,
                        onRecord: { keyCode, modifiers in
                            settings.navUpKeyCode = keyCode
                            settings.navUpModifiers = modifiers.rawValue
                            settings.navUpDisplay = AppSettings.displayString(for: keyCode, modifiers: modifiers)
                        }
                    )
                    
                    ShortcutRecorderRow(
                        label: "Navigate Down",
                        displayString: $settings.navDownDisplay,
                        isGlobalHotkey: false,
                        onRecord: { keyCode, modifiers in
                            settings.navDownKeyCode = keyCode
                            settings.navDownModifiers = modifiers.rawValue
                            settings.navDownDisplay = AppSettings.displayString(for: keyCode, modifiers: modifiers)
                        }
                    )
                    
                    Button(action: {
                        settings.resetShortcutsToDefaults()
                    }) {
                        Text("Reset to Defaults")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                
                Divider()
                
                // About section
                VStack(alignment: .leading, spacing: 12) {
                    Text("ABOUT")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2.1")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Pasteboard")
                        Spacer()
                        Text("macOS Clipboard Manager")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    HStack {
                        Text("Source Code")
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://github.com/nahid0-0/Pasteboard") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                Text("GitHub")
                            }
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .frame(width: 460, height: 580)
    }
}

// MARK: - Shortcut Recorder Row

struct ShortcutRecorderRow: View {
    let label: String
    @Binding var displayString: String
    let isGlobalHotkey: Bool
    let onRecord: (UInt16, NSEvent.ModifierFlags) -> Void
    
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
            
            Spacer()
            
            if isRecording {
                Text("Press shortcut…")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    )
                    .onAppear { startRecording() }
                
                Button("Cancel") {
                    stopRecording()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            } else {
                Text(displayString)
                    .font(.system(size: 11, design: .rounded).weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.secondary.opacity(0.15))
                    )
                
                Button("Record") {
                    isRecording = true
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
    }
    
    private func startRecording() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only keep the four standard modifiers; arrow keys add .numericPad/.function
            let standardMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let modifiers = event.modifierFlags.intersection(standardMask)
            
            // Require at least one modifier for the global hotkey
            if isGlobalHotkey {
                let hasModifier = modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control)
                guard hasModifier else { return event }
            }
            
            onRecord(event.keyCode, modifiers)
            stopRecording()
            return nil  // consume the event
        }
    }
    
    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
    }
}
