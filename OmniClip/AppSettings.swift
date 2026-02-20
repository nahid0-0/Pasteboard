import SwiftUI

class AppSettings: ObservableObject {
    @Published var copyOnClick: Bool {
        didSet {
            UserDefaults.standard.set(copyOnClick, forKey: "copyOnClick")
        }
    }
    
    @Published var captureScreenshots: Bool {
        didSet {
            UserDefaults.standard.set(captureScreenshots, forKey: "captureScreenshots")
        }
    }
    
    @Published var openURLsInBrowser: Bool {
        didSet {
            UserDefaults.standard.set(openURLsInBrowser, forKey: "openURLsInBrowser")
        }
    }
    
    @Published var syntaxHighlighting: Bool {
        didSet {
            UserDefaults.standard.set(syntaxHighlighting, forKey: "syntaxHighlighting")
        }
    }
    
    @Published var usePopupMode: Bool {
        didSet {
            UserDefaults.standard.set(usePopupMode, forKey: "usePopupMode")
        }
    }
    
    init() {
        if UserDefaults.standard.object(forKey: "copyOnClick") != nil {
            self.copyOnClick = UserDefaults.standard.bool(forKey: "copyOnClick")
        } else {
            self.copyOnClick = false
        }
        
        if UserDefaults.standard.object(forKey: "captureScreenshots") != nil {
            self.captureScreenshots = UserDefaults.standard.bool(forKey: "captureScreenshots")
        } else {
            self.captureScreenshots = true
        }
        
        if UserDefaults.standard.object(forKey: "openURLsInBrowser") != nil {
            self.openURLsInBrowser = UserDefaults.standard.bool(forKey: "openURLsInBrowser")
        } else {
            self.openURLsInBrowser = true
        }
        
        if UserDefaults.standard.object(forKey: "syntaxHighlighting") != nil {
            self.syntaxHighlighting = UserDefaults.standard.bool(forKey: "syntaxHighlighting")
        } else {
            self.syntaxHighlighting = true
        }
        
        if UserDefaults.standard.object(forKey: "usePopupMode") != nil {
            self.usePopupMode = UserDefaults.standard.bool(forKey: "usePopupMode")
        } else {
            self.usePopupMode = false
        }
    }
}
