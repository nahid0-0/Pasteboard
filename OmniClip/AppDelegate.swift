import Cocoa
import SwiftUI
import Combine
import Carbon

// Shared keyboard action publisher - owned by AppDelegate, observed by ContentView
class KeyboardActionPublisher: ObservableObject {
    @Published var actionCounter: Int = 0
    var lastAction: String = ""  // "up", "down", "enter", "search"
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var panel: NSPanel!
    private var clipboardManager: ClipboardManager!
    private var noteManager: NoteManager!
    private var appSettings: AppSettings!
    private var settingsObserver: AnyCancellable?
    private var hotkeyObservers: [AnyCancellable] = []
    private var hotKeyRef: EventHotKeyRef?
    private var stackModeHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var keyMonitor: Any?
    private var stackModeObserver: AnyCancellable?
    private var floatingObserver: AnyCancellable?
    
    // Shared with panel's ContentView and titlebar toolbar
    let keyboardActions = KeyboardActionPublisher()
    let toolbarState = ToolbarState()
    let navigation = NavigationState()

    // Separate state for the popover — independent navigation from the panel
    let popoverNavigation = NavigationState()
    let popoverToolbarState: ToolbarState = {
        let s = ToolbarState()
        s.isPopoverMode = true   // always in popover mode — toolbar is inline
        return s
    }()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        appSettings = AppSettings()
        clipboardManager = ClipboardManager()
        noteManager = NoteManager()
        
        clipboardManager.configureScreenshotWatcher(enabled: appSettings.captureScreenshots)
        
        settingsObserver = appSettings.$captureScreenshots.sink { [weak self] enabled in
            self?.clipboardManager.configureScreenshotWatcher(enabled: enabled)
        }
        
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            // App glyph (paperclip stack) as a template image so it adapts to light/dark menu bars.
            // NSImage(named:) picks up menubar_icon.png + menubar_icon@2x.png from Resources.
            if let icon = NSImage(named: "menubar_icon") {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true
                icon.accessibilityDescription = "Pasteboard"
                button.image = icon
            } else {
                let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
                button.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Pasteboard")?.withSymbolConfiguration(config)
            }
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Observe stack mode to show/hide the blue marker on the status bar icon.
        // The marker sits to the LEFT of the glyph: while stacking, the button image is
        // swapped for a copy with transparent space on its left, and the marker is
        // placed in that space so it never overlaps the icon.
        let baseIcon = statusItem.button?.image
        stackModeObserver = clipboardManager.$isStackMode.sink { [weak self] isActive in
            guard let self = self, let button = self.statusItem.button else { return }
            let dotID = "stackModeDot"
            let markerWidth: CGFloat = 6, markerHeight: CGFloat = 12, gap: CGFloat = 3

            button.subviews.first(where: { $0.accessibilityIdentifier() == dotID })?.removeFromSuperview()

            guard isActive, let icon = baseIcon else {
                button.image = baseIcon
                return
            }

            // Template image = [marker space][gap][icon]
            let leftPad = markerWidth + gap
            let padded = NSImage(size: NSSize(width: icon.size.width + leftPad, height: icon.size.height),
                                 flipped: false) { rect in
                icon.draw(in: NSRect(x: leftPad, y: 0, width: icon.size.width, height: icon.size.height))
                return true
            }
            padded.isTemplate = true
            padded.accessibilityDescription = icon.accessibilityDescription
            button.image = padded

            // Place the marker once the button has resized for the wider image
            DispatchQueue.main.async {
                // Stack mode may have been switched off again in the meantime
                guard self.clipboardManager.isStackMode,
                      !button.subviews.contains(where: { $0.accessibilityIdentifier() == dotID }) else { return }
                let imageX = (button.bounds.width - padded.size.width) / 2
                let marker = NSView(frame: NSRect(x: imageX,
                                                  y: (button.bounds.height - markerHeight) / 2,
                                                  width: markerWidth,
                                                  height: markerHeight))
                marker.wantsLayer = true
                marker.layer?.backgroundColor = NSColor.systemBlue.cgColor
                marker.layer?.cornerRadius = 3
                marker.setAccessibilityIdentifier(dotID)
                button.addSubview(marker)
            }
        }
        
        // Create popover (menu bar dropdown mode) — uses its own navigation & toolbar state
        // so popover and panel page selections are fully independent.
        let popoverContentView = RootView(
            navigation: popoverNavigation,
            clipboardManager: clipboardManager,
            noteManager: noteManager,
            appSettings: appSettings,
            keyboardActions: keyboardActions,
            toolbarState: popoverToolbarState
        )
        popover = NSPopover()
        popover.contentSize = NSSize(width: 900, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: popoverContentView)
        popover.appearance = NSAppearance(named: .darkAqua)
        
        let panelContentView = RootView(
            navigation: navigation,
            clipboardManager: clipboardManager,
            noteManager: noteManager,
            appSettings: appSettings,
            keyboardActions: keyboardActions,
            toolbarState: toolbarState
        )
        
        // Create panel (centered popup / keyboard mode)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.title = "Pasteboard"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.contentView = NSHostingView(rootView: panelContentView)
        panel.delegate = self
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.minSize = NSSize(width: 700, height: 400)
        
        // Observe float toggle — must be after panel is created
        floatingObserver = appSettings.$isFloating.sink { [weak self] floating in
            guard let self = self else { return }
            self.panel.hidesOnDeactivate = !floating
            self.panel.level = floating ? .floating : .normal
            if floating {
                self.panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            } else {
                self.panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
            }
        }
        
        // Embed navigation-aware toolbar in the titlebar row
        let titlebarAccessory = NSTitlebarAccessoryViewController()
        let toolbarView = TitlebarToolbarView(
            toolbarState: toolbarState,
            clipboardManager: clipboardManager,
            appSettings: appSettings
        )
        .environmentObject(navigation)
        titlebarAccessory.view = NSHostingView(rootView: toolbarView)
        titlebarAccessory.layoutAttribute = .bottom
        panel.addTitlebarAccessoryViewController(titlebarAccessory)
        
        // Register global hotkeys from settings
        registerGlobalHotKey()
        
        // Watch for hotkey setting changes
        observeHotkeySettings()
        
        // Set up keyboard monitor for navigation
        setupKeyboardMonitor()
        
        // Listen for dismiss notification from ContentView (Enter key)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismiss),
            name: .dismissOmniClip,
            object: nil
        )
    }
    
    // MARK: - Hotkey Settings Observers
    
    private func observeHotkeySettings() {
        let keyCodeObs = appSettings.$toggleHotkeyKeyCode.dropFirst().sink { [weak self] _ in self?.reregisterHotKey() }
        let modObs = appSettings.$toggleHotkeyModifiers.dropFirst().sink { [weak self] _ in self?.reregisterHotKey() }
        let enabledObs = appSettings.$keyboardModeEnabled.dropFirst().sink { [weak self] _ in self?.reregisterHotKey() }
        
        let stackKeyCodeObs = appSettings.$stackModeHotkeyKeyCode.dropFirst().sink { [weak self] _ in self?.reregisterHotKey() }
        let stackModObs = appSettings.$stackModeHotkeyModifiers.dropFirst().sink { [weak self] _ in self?.reregisterHotKey() }
        let stackEnabledObs = appSettings.$stackModeHotkeyEnabled.dropFirst().sink { [weak self] _ in self?.reregisterHotKey() }
        
        hotkeyObservers = [keyCodeObs, modObs, enabledObs, stackKeyCodeObs, stackModObs, stackEnabledObs]
    }
    
    private func reregisterHotKey() {
        unregisterGlobalHotKey()
        registerGlobalHotKey()
    }
    
    @objc private func handleDismiss() {
        if popover.isShown {
            popover.performClose(nil)
        }
        panel.orderOut(nil)
    }
    
    // MARK: - NSWindowDelegate (dismiss on click-away)

    /// The panel is non-activating, so Pasteboard may never become the active app and
    /// `hidesOnDeactivate` never fires — the panel would linger behind other windows or on
    /// another desktop while still "visible", so the next hotkey press would *hide* it.
    /// Hide it ourselves when focus moves to another app.
    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard !self.appSettings.isFloating,                      // floating = stay put
                  !self.panel.styleMask.contains(.fullScreen),
                  NSApp.keyWindow == nil,                           // focus left our app
                  NSApp.modalWindow == nil                          // not our own dialog
            else { return }
            self.panel.orderOut(nil)
        }
    }

    // MARK: - NSWindowDelegate (Fullscreen)
    
    func windowWillEnterFullScreen(_ notification: Notification) {
        panel.level = .normal
        panel.hidesOnDeactivate = false
    }
    
    func windowDidExitFullScreen(_ notification: Notification) {
        panel.level = .floating
        panel.hidesOnDeactivate = true
    }
    
    // MARK: - Keyboard Monitor (runs in AppDelegate for reliability)
    
    private func setupKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Only intercept when our popover or panel is visible
            let isVisible = self.popover.isShown || self.panel.isVisible
            guard isVisible else { return event }
            
            // Only compare the four standard modifiers; arrow keys add .numericPad/.function
            let standardMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let modifiers = event.modifierFlags.intersection(standardMask)
            let keyCode = event.keyCode
            
            // Navigate Up
            let navUpMods = NSEvent.ModifierFlags(rawValue: self.appSettings.navUpModifiers).intersection(standardMask)
            if keyCode == self.appSettings.navUpKeyCode && modifiers == navUpMods {
                self.keyboardActions.lastAction = "up"
                self.keyboardActions.actionCounter += 1
                return nil
            }
            
            // Navigate Down
            let navDownMods = NSEvent.ModifierFlags(rawValue: self.appSettings.navDownModifiers).intersection(standardMask)
            if keyCode == self.appSettings.navDownKeyCode && modifiers == navDownMods {
                self.keyboardActions.lastAction = "down"
                self.keyboardActions.actionCounter += 1
                return nil
            }
            
            // Shift+Left - focus search (keep hardcoded for simplicity)
            let shift = modifiers.contains(.shift)
            let cmd = modifiers.contains(.command)
            let opt = modifiers.contains(.option)
            let ctrl = modifiers.contains(.control)
            let plainModifiers = !cmd && !opt && !ctrl
            
            if keyCode == 123 && shift && plainModifiers {
                self.keyboardActions.lastAction = "search"
                self.keyboardActions.actionCounter += 1
                return nil
            }
            
            // Enter/Return
            if (keyCode == 36 || keyCode == 76) && !shift && plainModifiers {
                self.keyboardActions.lastAction = "enter"
                self.keyboardActions.actionCounter += 1
                return nil
            }
            
            return event
        }
    }
    
    // MARK: - Global Hotkey
    
    private func registerGlobalHotKey() {
        let needsHandler = appSettings.keyboardModeEnabled || appSettings.stackModeHotkeyEnabled
        guard needsHandler else { return }
        
        if eventHandlerRef == nil {
            var eventType = EventTypeSpec()
            eventType.eventClass = OSType(kEventClassKeyboard)
            eventType.eventKind = UInt32(kEventHotKeyPressed)
            
            var handlerRef: EventHandlerRef?
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, event, userData) -> OSStatus in
                    guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }
                    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                    
                    var hotKeyID = EventHotKeyID()
                    let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                    
                    let id = (err == noErr) ? hotKeyID.id : 1
                    
                    DispatchQueue.main.async {
                        if id == 1 {
                            delegate.handleGlobalHotKey()
                        } else if id == 2 {
                            delegate.handleStackModeHotKey()
                        }
                    }
                    return noErr
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &handlerRef
            )
            
            if status == noErr {
                eventHandlerRef = handlerRef
            }
        }
        
        if appSettings.keyboardModeEnabled {
            var hotKeyID = EventHotKeyID()
            hotKeyID.signature = OSType(0x4F43_4C50)
            hotKeyID.id = 1
            RegisterEventHotKey(appSettings.toggleHotkeyKeyCode, appSettings.toggleHotkeyModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        }
        
        if appSettings.stackModeHotkeyEnabled {
            var stackModeID = EventHotKeyID()
            stackModeID.signature = OSType(0x4F43_4C50)
            stackModeID.id = 2
            RegisterEventHotKey(appSettings.stackModeHotkeyKeyCode, appSettings.stackModeHotkeyModifiers, stackModeID, GetApplicationEventTarget(), 0, &stackModeHotKeyRef)
        }
    }
    
    private func unregisterGlobalHotKey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let stackModeHotKeyRef = stackModeHotKeyRef {
            UnregisterEventHotKey(stackModeHotKeyRef)
            self.stackModeHotKeyRef = nil
        }
        if let handlerRef = eventHandlerRef {
            RemoveEventHandler(handlerRef)
            self.eventHandlerRef = nil
        }
    }
    
    @objc func handleStackModeHotKey() {
        clipboardManager.toggleStackMode()
    }
    
    /// True only when the panel is really in front of the user (on this desktop, focused).
    /// `panel.isVisible` alone can be true for a panel left behind other windows or on
    /// another desktop — using it made the first hotkey press hide an unseen window.
    private var isPanelInFront: Bool {
        panel.isVisible && panel.isKeyWindow && panel.isOnActiveSpace
    }

    private func showPanel() {
        if popover.isShown {
            popover.performClose(nil)
        }
        toolbarState.isPopoverMode = false
        centerPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()   // show even if activation is refused/delayed
    }

    @objc func handleGlobalHotKey() {
        if isPanelInFront {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }
    
    // MARK: - Status Item Click
    
    @objc func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            showContextMenu()
            return
        }
        
        if appSettings.usePopupMode {
            togglePanel()
        } else {
            togglePopover()
        }
    }
    
    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            panel.orderOut(nil)
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func togglePanel() {
        if isPanelInFront {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }
    
    private func centerPanel() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.midY - panelFrame.height / 2 + 10
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    // MARK: - Dismiss
    
    private func dismissAll() {
        if popover.isShown {
            popover.performClose(nil)
        }
        panel.orderOut(nil)
    }
    
    // MARK: - Context Menu
    
    @objc func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Pasteboard", action: #selector(quitApp), keyEquivalent: "q"))
        
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        clipboardManager.stopMonitoring()
        unregisterGlobalHotKey()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
