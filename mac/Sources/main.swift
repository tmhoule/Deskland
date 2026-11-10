import AppKit
import ApplicationServices
import WebKit

final class WallpaperWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var settingsWindow: NSWindow?
    private var settingsView: WKWebView?
    private var settingsReady = false
    private var store: SettingsStore!
    private var activeTheme = "beach"
    private var statusItem: NSStatusItem!
    private var iconTimer: Timer?
    private var diagnosticsTimer: Timer?
    private let provider = FinderIconProvider()
    private let iconQueue = DispatchQueue(label: "DesklandPreview.FinderGeometry", qos: .utility)
    private var reading = false
    private var ready = false
    private var pauseReasons = Set<String>()
    private var lastIconMessage = ""
    private var lastSettingsIconMessage = ""
    private var lastSettingsStatus = ""
    private var displayBounds = CGRect.zero
    private var latest: [String: Any] = [:]
    private var latestIconStatus = "starting"
    private var latestIconDetail = ""
    private var settingsIconStatus = "unavailable"
    private var previousFrames: Int?
    private var previousSample: Date?
    private var restarts = 0
    private var smokeFrames: [Int] = []
    private var smokePausedFrames: [Int] = []
    private var smokeResumedFrames: [Int] = []
    private var smokeDidResume = false
    private var smokeErrors = false
    private var iconStatusMenuItem: NSMenuItem!
    private let arguments = CommandLine.arguments
    private var smoke: Bool { arguments.contains("--smoke-test") }
    private var windowed: Bool { arguments.contains("--windowed") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let resources = Bundle.main.resourceURL!.appendingPathComponent("prototype")
        let profile: URL
        if let index = arguments.firstIndex(of: "--profile-dir"), arguments.indices.contains(index + 1) {
            profile = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            profile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DesklandPreview")
        }
        do { store = try SettingsStore(registry: resources.appendingPathComponent("themes.json"), directory: profile) }
        catch {
            let chinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
            let alert = NSAlert()
            alert.messageText = chinese ? "无法打开 Deskland Preview" : "Cannot open Deskland Preview"
            alert.informativeText = chinese ? "无法读取主题配置或保存设置。请检查应用和设置文件夹权限。" : "The theme configuration could not be read or settings could not be saved. Check app and settings folder permissions."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            exit(1)
        }
        activeTheme = store.theme
        if let override = arguments.first(where: { $0.hasPrefix("--theme=") })?.components(separatedBy: "=").last,
           store.rules[override] != nil { activeTheme = override }
        makeMenu()
        makeSurface()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(waking), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionInactive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(refreshDisplay), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshDisplay), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        iconTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.readIcons() }
        diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sampleDiagnostics() }
        if !smoke || arguments.contains("--settings") { showSettings() }
        if smoke {
            if arguments.contains("--settings") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self = self else { return }
                    self.settingsWindow?.close()
                    self.latest["settingsReleasedOnClose"] = self.settingsWindow == nil && self.settingsView == nil && !self.settingsReady
                    self.showSettings()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.pauseReasons.insert("manual")
                self?.sendPause()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
                self?.pauseReasons.remove("manual")
                self?.smokeDidResume = true
                self?.sendPause()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.finishSmokeTest() }
        }
    }

    private var systemLanguage: String { Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-CN" : "en" }
    private var effectiveLanguage: String { store.lang == "auto" ? systemLanguage : store.lang }
    private func tr(_ zh: String, _ en: String) -> String { effectiveLanguage == "zh-CN" ? zh : en }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let resources = Bundle.main.resourceURL!
        configuration.setURLSchemeHandler(ResourceScheme(root: resources.appendingPathComponent("prototype")), forURLScheme: "deskland")
        configuration.userContentController.add(self, name: "deskland")
        let script = try! String(contentsOf: resources.appendingPathComponent("bridge.js"), encoding: .utf8)
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        return view
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 150, y: 150, width: 1100, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Deskland Preview"
            window.minSize = NSSize(width: 820, height: 600)
            window.isReleasedWhenClosed = false
            window.delegate = self
            let view = makeWebView()
            window.contentView = view
            settingsWindow = window; settingsView = view
            view.load(URLRequest(url: URL(string: "deskland://app/settings.html")!))
        }
        updatePermission()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow, closed === settingsWindow else { return }
        settingsReady = false
        settingsView?.stopLoading()
        settingsView?.configuration.userContentController.removeScriptMessageHandler(forName: "deskland")
        settingsView?.navigationDelegate = nil
        closed.contentView = nil
        settingsView = nil
        settingsWindow = nil
        lastSettingsIconMessage = ""
        lastSettingsStatus = ""
    }
    private func updatePermission() {
        if !AXIsProcessTrusted() {
            sendSettings(["t": "iconStatus", "status": "denied", "detail": "Accessibility permission is not granted."])
        }
    }

    private func sendSettings(_ message: [String: Any]) {
        guard settingsReady else { return }
        settingsView?.callAsyncJavaScript("window.__desklandReceive(message)", arguments: ["message": message], in: nil, in: .page, completionHandler: nil)
    }
    private func sendInit() {
        sendSettings(["t": "init", "theme": activeTheme, "params": store.params,
                      "screen": ["w": displayBounds.width, "h": displayBounds.height, "coordinateScale": 1],
                      "iconsScale": 1, "lang": store.lang, "langEff": effectiveLanguage, "langSys": systemLanguage,
                      "autostart": false, "iconStatus": ["status": settingsIconStatus, "detail": latestIconDetail],
                      "capabilities": ["share": false, "autostart": false, "updates": false, "saveAcknowledgement": true]])
    }

    private func makeMenu() {
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) }
        statusItem.button?.title = "Deskland"
        let menu = NSMenu()
        iconStatusMenuItem = NSMenuItem(title: tr("图标：正在读取", "Icons: starting"), action: nil, keyEquivalent: "")
        menu.addItem(iconStatusMenuItem)
        menu.addItem(.separator())
        for (title, action) in [
            (tr("设置…", "Settings…"), #selector(showSettings)),
            (tr("诊断…", "Diagnostics…"), #selector(showDiagnostics)),
            (tr("暂停 / 恢复", "Pause / Resume"), #selector(togglePause)),
            (tr("启用图标适配…", "Enable Icon Adaptation…"), #selector(requestAccessibility)),
            (tr("重新载入壁纸", "Reload Wallpaper"), #selector(reload)),
            (tr("退出 Deskland Preview", "Quit Deskland Preview"), #selector(quit))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        statusItem.menu = menu
    }

    private func makeSurface() {
        webView = makeWebView()
        webView.navigationDelegate = self
        if windowed {
            window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 1000, height: 650),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Deskland Preview — P1 comparison window"
            window.isReleasedWhenClosed = false
        } else {
            window = WallpaperWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
        }
        window.hasShadow = false
        window.backgroundColor = .black
        window.contentView = webView
        refreshDisplay()
        window.orderFrontRegardless()
        reload()
    }

    @objc private func refreshDisplay() {
        let mainID = CGMainDisplayID()
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == mainID
        }) else { return }
        displayBounds = CGDisplayBounds(mainID)
        if !windowed { window.setFrame(screen.frame, display: true) }
        lastIconMessage = ""
        lastSettingsIconMessage = ""
        let mode = CGDisplayCopyDisplayMode(mainID)
        latest["targetDisplay"] = ["id": mainID, "logicalWidth": displayBounds.width,
                                    "logicalHeight": displayBounds.height, "scale": screen.backingScaleFactor,
                                    "pixelWidth": mode?.pixelWidth ?? 0, "pixelHeight": mode?.pixelHeight ?? 0]
        if settingsReady {
            sendSettings(["t": "screen", "screen": ["w": displayBounds.width, "h": displayBounds.height, "coordinateScale": 1]])
        }
        readIcons()
    }

    @objc private func reload() {
        ready = false
        lastIconMessage = ""
        previousFrames = nil
        previousSample = nil
        webView.load(URLRequest(url: URL(string: "deskland://app/\(activeTheme == "meadow" ? "meadow.html" : "flat.html")?wallpaper=1")!))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.scheme == "deskland",
              message.frameInfo.request.url?.host == "app",
              message.frameInfo.request.url?.path == (message.webView === settingsView ? "/settings.html" : (activeTheme == "meadow" ? "/meadow.html" : "/flat.html")),
              let raw = message.body as? String else { return }
        let isSettings = message.webView === settingsView
        if isSettings {
            guard let data = raw.data(using: .utf8), let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = m["t"] as? String else { return }
            if type == "hello" { settingsReady = true; sendInit(); lastIconMessage = ""; lastSettingsIconMessage = ""; lastSettingsStatus = ""; readIcons(); return }
            do {
                switch type {
                case "theme":
                    guard let id = m["id"] as? String else { return }
                    try store.select(id); activeTheme = id; reload()
                    sendSettings(["t": "themeChanged", "id": id])
                case "set":
                    guard let id = m["theme"] as? String, let key = m["key"] as? String, let value = m["value"] else { return }
                    try store.set(theme: id, key: key, value: value)
                    if id == activeTheme { send(["t": "settings", "v": store.params[id] ?? [:]]) }
                case "lang":
                    guard let value = m["v"] as? String else { return }
                    try store.language(value); makeMenu(); updatePermission()
                    sendSettings(["t": "lang", "v": store.lang, "eff": effectiveLanguage, "sys": systemLanguage])
                case "requestAccessibility": requestAccessibility(); return
                case "openWebsite":
                    NSWorkspace.shared.open(URL(string: "https://deskland.app")!); return
                default: return
                }
                var ack: [String: Any] = ["t": "saveStatus", "ok": true]
                if let requestId = m["requestId"] as? NSNumber { ack["requestId"] = requestId }
                sendSettings(ack)
            } catch {
                var ack: [String: Any] = ["t": "saveStatus", "ok": false, "msg": tr("设置未保存，请检查磁盘权限。", "Settings were not saved. Check disk permissions.")]
                if let requestId = m["requestId"] as? NSNumber { ack["requestId"] = requestId }
                sendSettings(ack)
            }
            return
        }
        guard message.webView === webView, raw == "ready" else { return }
        ready = true
        var values: [String: Any] = store.params[activeTheme] ?? [:]
        values["cap30"] = true
        send(["t": "settings", "v": values])
        sendPause()
        lastIconMessage = ""
        readIcons()
    }

    private func send(_ message: [String: Any]) {
        guard ready else { return }
        webView.callAsyncJavaScript("window.__desklandReceive(message)", arguments: ["message": message],
                                    in: nil, in: .page) { [weak self] result in
            if case .failure = result { self?.latest["bridgeError"] = true }
        }
    }

    private func readIcons() {
        guard ready, !reading, !pauseReasons.contains("sleep"), !pauseReasons.contains("session") else { return }
        reading = true
        iconQueue.async { [weak self] in
            guard let self = self else { return }
            let snapshot = self.provider.read()
            DispatchQueue.main.async {
                self.reading = false
                self.latestIconStatus = snapshot.status
                self.latestIconDetail = snapshot.detail
                self.settingsIconStatus = snapshot.status == "permissionRequired" ? "denied" : (snapshot.status == "ready" ? (snapshot.rectangles.isEmpty ? "empty" : "ready") : "unavailable")
                let statusSignature = self.settingsIconStatus + "|" + snapshot.detail
                if statusSignature != self.lastSettingsStatus {
                    self.lastSettingsStatus = statusSignature
                    self.sendSettings(["t": "iconStatus", "status": self.settingsIconStatus, "detail": snapshot.detail])
                }
                self.iconStatusMenuItem.title = snapshot.status == "ready"
                    ? self.tr("图标：正在读取桌面位置", "Icons: reading desktop geometry")
                    : self.tr("图标：不可用（查看诊断）", "Icons: unavailable (see diagnostics)")
                // Windowed mode maps the whole desktop into its viewport for comparison.
                // Desktop mode uses exact logical coordinates with no rounding.
                var rectangles = DesktopGeometry.localRectangles(snapshot.rectangles, displayBounds: self.displayBounds)
                let settingsMessage: [String: Any] = ["t": "icons", "vis": snapshot.status == "ready", "r": rectangles, "iconsScale": 1]
                if let data = try? JSONSerialization.data(withJSONObject: settingsMessage, options: .sortedKeys),
                   let signature = String(data: data, encoding: .utf8), signature != self.lastSettingsIconMessage {
                    self.lastSettingsIconMessage = signature
                    self.sendSettings(settingsMessage)
                }
                if self.windowed, self.displayBounds.width > 0, self.displayBounds.height > 0 {
                    let size = self.webView.bounds.size
                    rectangles = rectangles.map { [$0[0] * size.width / self.displayBounds.width,
                                                   $0[1] * size.height / self.displayBounds.height,
                                                   $0[2] * size.width / self.displayBounds.width,
                                                   $0[3] * size.height / self.displayBounds.height] }
                }
                let message: [String: Any] = ["t": "icons", "vis": snapshot.status == "ready", "r": rectangles]
                if let data = try? JSONSerialization.data(withJSONObject: message, options: .sortedKeys),
                   let signature = String(data: data, encoding: .utf8), signature != self.lastIconMessage {
                    self.lastIconMessage = signature
                    self.send(message)
                }
            }
        }
    }

    private func sendPause() { send(["t": "pause", "v": !pauseReasons.isEmpty]) }
    @objc private func togglePause() {
        if pauseReasons.contains("manual") { pauseReasons.remove("manual") } else { pauseReasons.insert("manual") }
        sendPause()
    }
    @objc private func sleeping() { pauseReasons.insert("sleep"); sendPause() }
    @objc private func waking() { pauseReasons.remove("sleep"); refreshDisplay(); sendPause() }
    @objc private func sessionInactive() { pauseReasons.insert("session"); sendPause() }
    @objc private func sessionActive() { pauseReasons.remove("session"); refreshDisplay(); sendPause() }
    @objc private func requestAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        // The prompt is often suppressed after denial; open the relevant pane on this explicit action.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        updatePermission()
    }

    private func sampleDiagnostics() {
        if settingsReady {
            settingsView?.evaluateJavaScript("""
                (() => ({ready:document.documentElement.classList.contains('ready'), theme:state.theme, params:state.params,
                  screen:state.screen, thumbs:[...document.querySelectorAll('.thumb img')].map(i=>i.complete&&i.naturalWidth>0),
                  shareHidden:document.getElementById('share').hidden,
                  autostartDisabled:document.getElementById('autostart').disabled,
                  updatesHidden:document.getElementById('updateNotice').hidden,
                  preview:document.querySelector('iframe')?.contentWindow.__desklandDiagnostics?.(),
                  saveAcknowledgement:state.capabilities.saveAcknowledgement}))()
                """) { [weak self] value, error in
                    if let value = value as? [String: Any] { self?.latest["settings"] = value }
                    if error != nil { self?.latest["settingsDiagnosticError"] = true }
                }
        }
        guard ready else { latest["ready"] = false; return }
        webView.evaluateJavaScript("window.__desklandDiagnostics()") { [weak self] value, error in
            guard let self = self else { return }
            self.latest["ready"] = self.ready
            self.latest["iconStatus"] = self.latestIconStatus
            self.latest["iconDetail"] = self.latestIconDetail
            self.latest["pauseReasons"] = self.pauseReasons.sorted()
            self.latest["mode"] = self.windowed ? "windowed" : "desktop"
            if let diagnostic = value as? [String: Any] {
                self.latest["web"] = diagnostic
                let now = Date()
                if let frames = diagnostic["frames"] as? Int {
                    if let previous = self.previousFrames, let time = self.previousSample {
                        self.latest["observedRenderFPS"] = Double(max(0, frames - previous)) / now.timeIntervalSince(time)
                    }
                    self.previousFrames = frames
                    self.previousSample = now
                    if self.smoke {
                        self.smokeFrames.append(frames)
                        if self.pauseReasons.contains("manual") { self.smokePausedFrames.append(frames) }
                        if self.smokeDidResume { self.smokeResumedFrames.append(frames) }
                    }
                }
                if diagnostic["contextLost"] as? Bool == true { self.smokeErrors = true }
                if let errors = diagnostic["errors"] as? [String], !errors.isEmpty { self.smokeErrors = true }
            }
            if error != nil { self.latest["diagnosticError"] = true; self.smokeErrors = true }
        }
    }

    @objc private func showDiagnostics() {
        let data = (try? JSONSerialization.data(withJSONObject: latest, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let alert = NSAlert()
        alert.messageText = "Deskland Preview — P1"
        alert.informativeText = "Icon adaptation: \(latestIconStatus)\n\(latestIconDetail)\n\nThis is a P1 preview, not a finished Mac release.\nNo filenames, screenshots, or file paths are collected."
        let text = NSTextView(frame: CGRect(x: 0, y: 0, width: 560, height: 300))
        text.string = String(data: data, encoding: .utf8) ?? "No diagnostics yet"
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let scroll = NSScrollView(frame: text.frame)
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        alert.accessoryView = scroll
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func finishSmokeTest() {
        let web = latest["web"] as? [String: Any] ?? [:]
        let advanced = (smokeFrames.last ?? 0) > (smokeFrames.first ?? 0)
        let stopped = smokePausedFrames.count >= 2 && smokePausedFrames.first == smokePausedFrames.last
        let resumed = smokeResumedFrames.count >= 2 && (smokeResumedFrames.last ?? 0) > (smokeResumedFrames.first ?? 0)
        let canvas = web["canvas"] as? [Int] ?? []
        let canvasValid = canvas.count == 2 && canvas.allSatisfy { $0 > 0 }
        let settings = latest["settings"] as? [String: Any] ?? [:]
        let thumbs = settings["thumbs"] as? [Bool] ?? []
        let preview = settings["preview"] as? [String: Any] ?? [:]
        let settingsParams = settings["params"] as? [String: [String: Double]] ?? [:]
        let settingsPassed = !arguments.contains("--settings") || (settingsReady && latest["settingsReleasedOnClose"] as? Bool == true && settings["ready"] as? Bool == true
            && thumbs.count == 13 && thumbs.allSatisfy { $0 } && settings["shareHidden"] as? Bool == true
            && settings["autostartDisabled"] as? Bool == true && settings["updatesHidden"] as? Bool == true
            && settings["saveAcknowledgement"] as? Bool == true && settings["theme"] as? String == activeTheme
            && settingsParams[activeTheme] == store.params[activeTheme]
            && preview["webgl"] as? Bool == true && (preview["frames"] as? Int ?? 0) > 0)
        latest["settingsSmokePassed"] = settingsPassed
        let passed = settingsPassed && ready && advanced && stopped && resumed && canvasValid
            && web["webgl"] as? Bool == true && web["contextLost"] as? Bool == false && !smokeErrors
        latest["theme"] = activeTheme
        latest["settingsReady"] = settingsReady
        latest["pauseStoppedRendering"] = stopped
        latest["resumeRestartedRendering"] = resumed
        latest["smokePassed"] = passed
        latest["note"] = "Smoke success proves rendering only; Finder permission and desktop integration require manual acceptance."
        if let data = try? JSONSerialization.data(withJSONObject: latest, options: [.prettyPrinted, .sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        // Shut down through AppKit; report test failure using process exit status.
        if !passed { exit(1) }
        NSApp.terminate(nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === settingsView { settingsReady = false; settingsView?.reload(); return }
        ready = false
        restarts += 1
        latest["webContentRestarts"] = restarts
        guard restarts <= 3 else { latest["fatal"] = "WebContent repeatedly terminated"; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(restarts)) { [weak self] in self?.reload() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, url.scheme == "deskland", url.host == "app",
              let frame = navigationAction.targetFrame else { decisionHandler(.cancel); return }
        let allowed: [String]
        if webView === settingsView { allowed = frame.isMainFrame ? ["/settings.html"] : ["/flat.html", "/meadow.html"] }
        else { allowed = [activeTheme == "meadow" ? "/meadow.html" : "/flat.html"] }
        decisionHandler(allowed.contains(url.path) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        latest["loadFailure"] = (error as NSError).code
        smokeErrors = true
    }

    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        iconTimer?.invalidate()
        diagnosticsTimer?.invalidate()
        settingsView?.configuration.userContentController.removeScriptMessageHandler(forName: "deskland")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "deskland")
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

let application = NSApplication.shared
// Launch Services normally enforces one process for this bundle. Also protect
// direct executable launches used during development without terminating peers.
if NSRunningApplication.runningApplications(withBundleIdentifier: "app.deskland.preview.mac.p0")
    .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    fputs("Deskland Preview P0 is already running. Quit it from its menu bar first.\n", stderr)
    exit(1)
}
let delegate = AppController()
application.delegate = delegate
application.run()
