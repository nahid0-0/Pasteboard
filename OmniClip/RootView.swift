import SwiftUI

/// The root view shared by both the NSPanel and the NSPopover.
/// It owns the inline toolbar (shown in popover mode) and switches pages.
struct RootView: View {
    @ObservedObject var navigation: NavigationState
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var noteManager: NoteManager
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var keyboardActions: KeyboardActionPublisher
    @ObservedObject var toolbarState: ToolbarState

    var body: some View {
        VStack(spacing: 0) {
            // ── Inline toolbar (popover only — panel uses NSTitlebarAccessoryViewController) ──
            if toolbarState.isPopoverMode {
                TitlebarToolbarView(
                    toolbarState: toolbarState,
                    clipboardManager: clipboardManager,
                    appSettings: appSettings
                )
                .padding(.horizontal, 6)
                .frame(height: 36)
                .background(appSettings.theme.mainBg)

                Divider().opacity(0.4)
            }

            // ── Page content ──────────────────────────────────────────
            ZStack {
                switch navigation.currentPage {
                case .clipboard:
                    ContentView(
                        clipboardManager: clipboardManager,
                        appSettings: appSettings,
                        keyboardActions: keyboardActions,
                        toolbarState: toolbarState
                    )
                    .transition(.opacity)

                case .notes:
                    NotesView(
                        noteManager: noteManager,
                        appSettings: appSettings,
                        toolbarState: toolbarState
                    )
                    .transition(.opacity)

                case .settings:
                    SettingsView(settings: appSettings)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: navigation.currentPage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Solid backdrop (extends under the titlebar) so the page cross-fade never
        // reveals the lighter window background — that caused a brief "glow" on switch.
        .background(appSettings.theme.mainBg)
        // Provide navigation to all child views (TitlebarToolbarView uses @EnvironmentObject)
        .environmentObject(navigation)
    }
}
