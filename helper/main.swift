// agentfocus helper: menu-bar queue + UN banners + global hotkey.
// One process owns all TCC surfaces (C1): AppleScript focusing runs through the
// CLI as a child, so Automation grants attribute here and nowhere else.
import Cocoa
import Carbon.HIToolbox
import ServiceManagement
import UserNotifications
import IOKit

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
    let id: String, title: String, term: String, ts: Double, oscNative: Bool, reason: String?
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    static var shared: AppDelegate!
    var statusItem: NSStatusItem!
    var notified = [String: Double]()  // session_id -> ts we bannered
    let staleMs: Double = 6 * 60 * 60 * 1000
    // Armed once you have been away long enough; fires on the poll where you are
    // back. A flag, not a timestamp, so the focus happens exactly once per return.
    var idleArmed = false
    // Seconds away before a return counts. Overridable only so the selftest can
    // use 10s instead of waiting five minutes; not documented as configuration.
    let returnAfter = UserDefaults.standard.object(forKey: "returnAfter") as? Double ?? 300

    func applicationWillFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        // Delegate must exist before launch finishes or a cold-launch banner
        // click is delivered to nobody.
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        log("launch")
        // On by default: the whole point is that you walk back and the agent that
        // needs you is already in front. Menu toggle turns it off.
        UserDefaults.standard.register(defaults: ["focusOnReturn": true])
        requestAuth(retry: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "AgentFocus")
        statusItem.button?.imagePosition = .imageLeading   // count sits beside the bell
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
        seedNotified {
            self.poll()
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in self.poll() }
        }
    }

    /// `notified` is the only record of what we've bannered, so an empty one on
    /// relaunch means we re-alert every waiting session AND orphan every banner
    /// the previous run posted (poll() can only clear ids it knows). Notification
    /// Center already holds that list — our identifiers ARE session ids — so seed
    /// from it. Async, and poll() must not run first; the deadline is there so a
    /// wedged notification daemon can never stop the helper from working at all.
    func seedNotified(_ done: @escaping () -> Void) {
        var fired = false
        let once = { if !fired { fired = true; done() } }
        UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
            DispatchQueue.main.async {
                for n in delivered { self.notified[n.request.identifier] = n.date.timeIntervalSince1970 * 1000 }
                // Delivered banners only cover what is still ON SCREEN. Dismiss a
                // banner without answering and the session stays waiting with
                // nothing in Notification Center, so a restart would banner it
                // again — the burst BUGS #7 is about, measured on this machine as
                // 20 re-alerts after one upgrade. A helper that has just started
                // has no business shouting about events that happened before it
                // existed: treat everything already waiting as already announced.
                // EXCEPT rows younger than the grace window — emit.js deliberately
                // writes the registry and THEN launches us, and that banner is the
                // entire point of the launch.
                let cutoff = Date().timeIntervalSince1970 * 1000 - 60_000
                var presumed = 0
                for s in self.readSessions() where s.ts < cutoff {
                    if self.notified[s.id] == nil { self.notified[s.id] = s.ts; presumed += 1 }
                }
                log("seeded \(delivered.count) delivered banner(s), \(presumed) already-waiting")
                once()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { once() }
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
                                   oscNative: (j["osc_native"] as? Bool) ?? false,
                                   reason: j["reason"] as? String))
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
            // emit.js writes the differentiated reason; `??` keeps rows from an
            // older emit.js (no `reason` field) rendering exactly as before.
            c.body = s.reason.map { "\($0) (\(s.term))" } ?? "waiting for input (\(s.term))"
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
            log("cleared \(cleared.count) banner(s)")
        }

        statusItem?.button?.image = NSImage(
            systemSymbolName: waiting.isEmpty ? "bell" : "bell.badge",
            accessibilityDescription: "AgentFocus")
        // How many are waiting, readable without opening the menu. No "running"
        // count: a row that is not waiting may be working or may have exited hours
        // ago, and the registry cannot tell those apart.
        statusItem?.button?.title = waiting.isEmpty ? "" : " \(waiting.count)"

        focusOnReturnIfBack(waiting)
    }

    // MARK: return-from-idle

    /// Seconds since the last keyboard/mouse event, system-wide — the same value
    /// `ioreg -c IOHIDSystem` prints. A public IORegistry property: no TCC, no
    /// Accessibility, nothing to grant.
    func idleSeconds() -> Double {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard svc != 0 else { return 0 }
        defer { IOObjectRelease(svc) }
        let p = IORegistryEntryCreateCFProperty(svc, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return ((p as? NSNumber)?.doubleValue ?? 0) / 1e9
    }

    /// Unlocked, and this login session owns the console. HIDIdleTime is ONE
    /// counter for the whole machine, so the password you type at the lock screen
    /// — and another user's typing after a fast user switch — both reset it.
    /// Without this the focus would fire behind loginwindow, where the first
    /// Automation prompt would appear somewhere you cannot see it.
    /// (Verified on macOS 26: the lock key is ABSENT when unlocked, so test != true.)
    func sessionUsable() -> Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (d["kCGSSessionOnConsoleKey"] as? Bool) == true
            && (d["CGSSessionScreenIsLocked"] as? Bool) != true
    }

    /// You walked away, something started waiting, you came back: put the oldest
    /// one in front. Edge-triggered, so it happens once per return, not every poll.
    func focusOnReturnIfBack(_ waiting: [Session]) {
        if idleSeconds() >= returnAfter { idleArmed = true; return }
        guard idleArmed, sessionUsable() else { return }
        idleArmed = false
        guard UserDefaults.standard.bool(forKey: "focusOnReturn") else { return }
        guard let oldest = waiting.last else { return }   // readSessions() is newest-first
        log("return from idle -> focus \(oldest.id)")
        runCLI(["focus", oldest.id])
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

    /// A focus YOU asked for also services the return-from-idle, so it must
    /// consume that edge. Clicking a banner (or pressing the hotkey) is itself the
    /// input that ends the idle period, so the very next poll would otherwise see
    /// "user is back" and fire a SECOND, automatic focus at a different session —
    /// not a rare race but the guaranteed outcome of the ordinary path: step away,
    /// an agent finishes, come back, click the banner. Two window raises land
    /// together and the editor merges both windows into one untitled workspace.
    func userFocus(_ args: [String]) {
        idleArmed = false
        runCLI(args)
    }

    @objc func focusNext() { userFocus(["focus-next"]) }
    @objc func focusSession(_ item: NSMenuItem) { userFocus(["focus", item.representedObject as! String]) }

    // MARK: notifications

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler h: @escaping () -> Void) {
        if let id = r.notification.request.content.userInfo["session_id"] as? String {
            log("click \(id)")
            userFocus(["focus", id])
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
            if let oldest = waiting.last {
                let age = Int((Date().timeIntervalSince1970 * 1000 - oldest.ts) / 60000)
                // action: nil renders disabled — a header, same as "No waiting agents".
                menu.addItem(NSMenuItem(title: "\(waiting.count) waiting · oldest \(age)m", action: nil, keyEquivalent: ""))
                menu.addItem(.separator())
            }
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
        let ret = NSMenuItem(title: "Focus on Return", action: #selector(toggleReturn), keyEquivalent: "")
        ret.target = self
        ret.state = UserDefaults.standard.bool(forKey: "focusOnReturn") ? .on : .off
        menu.addItem(ret)
        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Quit AgentFocus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func toggleReturn() {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: "focusOnReturn"), forKey: "focusOnReturn")
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

// `agentfocus uninstall` execs us with this flag: SMAppService registrations are
// owned by the app bundle, so deleting the bundle without unregistering leaves a
// dead "AgentFocus" row in System Settings > General > Login Items forever.
// Runs before any NSApplication setup — no menu bar, no polling, no banners.
if CommandLine.arguments.contains("--unregister-login-item") {
    try? SMAppService.mainApp.unregister()
    // Both .notFound and .notRegistered mean "no longer a login item" — the
    // former is what you get once the registration record is gone entirely.
    switch SMAppService.mainApp.status {
    case .notRegistered, .notFound: print("login item removed")
    case .enabled: print("still enabled — remove it in System Settings > General > Login Items")
    case .requiresApproval: print("awaiting your approval in System Settings > General > Login Items")
    @unknown default: print("status=\(SMAppService.mainApp.status.rawValue)")
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
