// agentfocus helper: menu-bar queue + UN banners + global hotkey.
// One process owns all TCC surfaces (C1): AppleScript focusing runs through the
// CLI as a child, so Automation grants attribute here and nowhere else.
import Cocoa
import Carbon.HIToolbox
import ServiceManagement
import UserNotifications

let HOME = FileManager.default.homeDirectoryForCurrentUser.path
let REGISTRY = HOME + "/.local/share/agentfocus/registry"
let CLI = HOME + "/.local/share/agentfocus/bin/agentfocus"
let LOG = HOME + "/Library/Logs/agentfocus/helper.log"

func log(_ s: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
    if let fh = FileHandle(forWritingAtPath: LOG) {
        fh.seekToEndOfFile(); fh.write(line.data(using: .utf8)!); fh.closeFile()
    } else {
        try? FileManager.default.createDirectory(atPath: (LOG as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? line.write(toFile: LOG, atomically: true, encoding: .utf8)
    }
}

struct Session {
    let id: String, title: String, term: String, ts: Double, oscNative: Bool
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    static var shared: AppDelegate!
    var statusItem: NSStatusItem!
    var notified = [String: Double]()  // session_id -> ts we bannered
    let staleMs: Double = 6 * 60 * 60 * 1000

    func applicationWillFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        // Delegate must exist before launch finishes or a cold-launch banner
        // click is delivered to nobody.
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        log("launch")
        requestAuth(retry: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "AgentFocus")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        registerHotKey()

        // Default-on login item, once; menu toggle owns it afterwards.
        let d = UserDefaults.standard
        if !d.bool(forKey: "loginItemHandled") {
            try? SMAppService.mainApp.register()
            d.set(true, forKey: "loginItemHandled")
            log("login item registered (first run)")
        }

        // ponytail: 2s poll instead of FSEvents — a dozen tiny JSONs, negligible
        // cost, and scan==watch so missed-event bugs can't exist. FSEvents if
        // latency ever matters.
        poll()
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in self.poll() }
    }

    func requestAuth(retry: Bool) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, err in
            log("UN auth granted=\(granted) err=\(err.map { "\($0)" } ?? "none")")
            if !granted && err != nil && retry {
                // First-ever request can spuriously fail on Tahoe; one retry.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.requestAuth(retry: false) }
            }
        }
    }

    // MARK: registry

    func readSessions() -> [Session] {
        var waiting = [Session]()
        let now = Date().timeIntervalSince1970 * 1000
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: REGISTRY) else { return [] }
        for f in files where f.hasSuffix(".json") {
            guard let data = FileManager.default.contents(atPath: REGISTRY + "/" + f),
                  let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = j["session_id"] as? String,
                  id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { continue }
            let ts = (j["ts"] as? Double) ?? 0
            guard (j["waiting"] as? Bool) == true, now - ts < staleMs else { continue }
            waiting.append(Session(id: id,
                                   title: (j["title"] as? String) ?? "agent",
                                   term: (j["term_program"] as? String) ?? "?",
                                   ts: ts,
                                   oscNative: (j["osc_native"] as? Bool) ?? false))
        }
        return waiting.sorted { $0.ts > $1.ts }
    }

    func poll() {
        let waiting = readSessions()
        let waitingIds = Set(waiting.map { $0.id })

        // Banner newly-waiting (or re-waiting: ts advanced) non-OSC sessions.
        for s in waiting where !s.oscNative {
            if let seen = notified[s.id], seen >= s.ts { continue }
            notified[s.id] = s.ts
            let c = UNMutableNotificationContent()
            c.title = "agentfocus: \(s.title)"
            c.body = "waiting for input (\(s.term))"
            c.userInfo = ["session_id": s.id]
            c.threadIdentifier = s.id
            c.interruptionLevel = .timeSensitive
            c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: s.id, content: c, trigger: nil)) { err in
                log("posted \(s.id) err=\(err.map { "\($0)" } ?? "none")")
            }
        }

        // Clear banners for sessions no longer waiting (answered/gone/stale).
        let cleared = notified.keys.filter { !waitingIds.contains($0) }
        if !cleared.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: cleared)
            cleared.forEach { notified.removeValue(forKey: $0) }
        }

        statusItem?.button?.image = NSImage(
            systemSymbolName: waiting.isEmpty ? "bell" : "bell.badge",
            accessibilityDescription: "AgentFocus")
    }

    // MARK: focus (via CLI — one place that knows the adapters)

    func runCLI(_ args: [String]) {
        guard args.allSatisfy({ $0.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil }) else { return }
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // Login shell so node (shebang of the CLI) is on PATH.
            p.arguments = ["-lc", "exec \"\(CLI)\" " + args.joined(separator: " ")]
            try? p.run(); p.waitUntilExit()
            log("cli \(args.joined(separator: " ")) exit=\(p.terminationStatus)")
        }
    }

    @objc func focusNext() { runCLI(["focus-next"]) }
    @objc func focusSession(_ item: NSMenuItem) { runCLI(["focus", item.representedObject as! String]) }

    // MARK: notifications

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler h: @escaping () -> Void) {
        if let id = r.notification.request.content.userInfo["session_id"] as? String {
            log("click \(id)")
            runCLI(["focus", id])
        }
        h()
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) {
        h([.banner, .sound])
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let waiting = readSessions()
        if waiting.isEmpty {
            menu.addItem(NSMenuItem(title: "No waiting agents", action: nil, keyEquivalent: ""))
        } else {
            for s in waiting {
                let age = Int((Date().timeIntervalSince1970 * 1000 - s.ts) / 60000)
                let item = NSMenuItem(title: "\(s.title)  (\(s.term), \(age)m)", action: #selector(focusSession(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = s.id
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let next = NSMenuItem(title: "Focus Next", action: #selector(focusNext), keyEquivalent: "a")
        next.keyEquivalentModifierMask = [.option, .command]
        next.target = self
        menu.addItem(next)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Quit AgentFocus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func toggleLogin() {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        else { try? SMAppService.mainApp.register() }
    }

    // MARK: hotkey

    var hotKeyRef: EventHotKeyRef?
    func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            AppDelegate.shared.focusNext()
            return noErr
        }, 1, &eventType, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4146_4B31), id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        log("hotkey opt+cmd+A status=\(status)")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
