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
    private var settingsWindow: NSWindow?
    private var clipboardManager: ClipboardManager!
    private var appSettings: AppSettings!
    private var settingsObserver: AnyCancellable?
    private var hotkeyObservers: [AnyCancellable] = []
    private var hotKeyRef: EventHotKeyRef?
    private var stackModeHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var keyMonitor: Any?
    private var stackModeObserver: AnyCancellable?
    
    // Shared with ContentView
    let keyboardActions = KeyboardActionPublisher()
    let toolbarState = ToolbarState()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        appSettings = AppSettings()
        clipboardManager = ClipboardManager()
        
        clipboardManager.configureScreenshotWatcher(enabled: appSettings.captureScreenshots)
        
        settingsObserver = appSettings.$captureScreenshots.sink { [weak self] enabled in
            self?.clipboardManager.configureScreenshotWatcher(enabled: enabled)
        }
        
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            button.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Pasteboard")?.withSymbolConfiguration(config)
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Observe stack mode to show/hide blue dot on status bar icon
        stackModeObserver = clipboardManager.$isStackMode.sink { [weak self] isActive in
            guard let self = self, let button = self.statusItem.button else { return }
            let dotID = "stackModeDot"
            if isActive {
                if button.subviews.first(where: { $0.accessibilityIdentifier() == dotID }) == nil {
                    let dot = NSView(frame: NSRect(x: button.bounds.width - 8, y: 6, width: 6, height: 6))
                    dot.wantsLayer = true
                    dot.layer?.backgroundColor = NSColor.systemBlue.cgColor
                    dot.layer?.cornerRadius = 3
                    dot.setAccessibilityIdentifier(dotID)
                    dot.autoresizingMask = [.minXMargin, .minYMargin]
                    button.addSubview(dot)
                }
            } else {
                button.subviews.first(where: { $0.accessibilityIdentifier() == dotID })?.removeFromSuperview()
            }
        }
        
        let popoverContentView = ContentView(
            clipboardManager: clipboardManager,
            appSettings: appSettings,
            keyboardActions: keyboardActions,
            toolbarState: toolbarState
        )
        
        // Create popover (menu bar dropdown mode)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 900, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: popoverContentView)
        
        let panelContentView = ContentView(
            clipboardManager: clipboardManager,
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
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.contentView = NSHostingView(rootView: panelContentView)
        panel.delegate = self
        panel.minSize = NSSize(width: 700, height: 400)
        
        // Embed toolbar in the titlebar row
        let titlebarAccessory = NSTitlebarAccessoryViewController()
        let toolbarView = TitlebarToolbarView(toolbarState: toolbarState, clipboardManager: clipboardManager)
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
        
        // Listen for settings notification from ContentView toolbar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openOmniClipSettings,
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
    
    @objc func handleGlobalHotKey() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            if popover.isShown {
                popover.performClose(nil)
            }
            toolbarState.isPopoverMode = false
            centerPanel()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
            toolbarState.isPopoverMode = true
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            if popover.isShown {
                popover.performClose(nil)
            }
            toolbarState.isPopoverMode = false
            centerPanel()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
    
    @objc func openSettings() {
        if popover.isShown {
            popover.performClose(nil)
        }
        panel.orderOut(nil)
        
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 580),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            // Prevent Cocoa from releasing the window on close (ARC already manages lifetime).
            // Without this, the second open crashes because the underlying object is freed.
            window.isReleasedWhenClosed = false
            window.title = "Pasteboard Settings"
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(settings: appSettings))
            // Nil out the reference when the user closes the window so it is recreated fresh next time
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.settingsWindow = nil
            }
            settingsWindow = window
        }
        
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
