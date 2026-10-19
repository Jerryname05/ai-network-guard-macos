import Cocoa
import Darwin

func mainland(_ location: String) -> Bool {
    let s = location.lowercased()
    if ["香港", "澳门", "澳門", "台湾", "臺灣", "hong kong", "macao", "macau", "taiwan"].contains(where: s.contains) { return false }
    return ["中国", "中國", "china"].contains(where: s.contains)
}
func validIP(_ s: String) -> Bool {
    var v4 = in_addr(); var v6 = in6_addr()
    return s.withCString { inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1 }
}
if CommandLine.arguments.contains("--test") {
    assert(mainland("中国 广东 深圳")); assert(!mainland("中国 香港"))
    assert(!mainland("美国 弗吉尼亚州 阿什本")); assert(!mainland("中国 台湾"))
    assert(validIP("65.195.105.59")); assert(!validIP("<html>")); assert(validIP("2001:db8::1"))
    print("PASS: 地区规则及 IPv4/IPv6 格式检查")
    exit(0)
}


final class OrbView: NSView {
    var toggle: (() -> Void)?
    var moved: (() -> Void)?
    var tint: NSColor = .systemOrange { didSet { needsDisplay = true } }
    var origin = NSPoint.zero
    var mouseOrigin = NSPoint.zero
    var dragged = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("蜘蛛侠网络守护，点击展开或收起，拖动移动")
        toolTip = "点击展开 / 收起 · 拖动移动 · 外圈为网络检测状态"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func accessibilityPerformPress() -> Bool { toggle?(); return true }
    override func mouseDown(with event: NSEvent) {
        mouseOrigin = NSEvent.mouseLocation; origin = window!.frame.origin; dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        if hypot(now.x-mouseOrigin.x, now.y-mouseOrigin.y) > 3 { dragged = true }
        if dragged {
            window?.setFrameOrigin(NSPoint(x: origin.x+now.x-mouseOrigin.x, y: origin.y+now.y-mouseOrigin.y))
            moved?()
        }
    }
    override func mouseUp(with event: NSEvent) {
        if !dragged { toggle?() }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.07, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3)).fill()
        tint.setStroke()
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 5, dy: 5)); ring.lineWidth = 3; ring.stroke()
        NSGraphicsContext.saveGraphicsState()
        let face = NSBezierPath(ovalIn: bounds.insetBy(dx: 12, dy: 12))
        face.addClip()
        NSColor(calibratedRed: 0.85, green: 0.07, blue: 0.14, alpha: 1).setFill(); face.fill()
        NSColor(calibratedWhite: 0.08, alpha: 0.85).setStroke()
        let center = NSPoint(x: 40, y: 39)
        for i in 0..<12 {
            let a = CGFloat(i) * .pi / 6
            let line = NSBezierPath(); line.move(to: center)
            line.line(to: NSPoint(x: center.x+50*cos(a), y: center.y+50*sin(a))); line.lineWidth=0.9; line.stroke()
        }
        for r in [12.0, 22.0, 33.0] {
            let web = NSBezierPath(ovalIn: NSRect(x: 40-r, y: 39-r, width: r*2, height: r*2))
            web.lineWidth = 0.9; web.stroke()
        }
        for mirrored in [false, true] {
            func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: mirrored ? 80-x : x, y:y) }
            let eye=NSBezierPath(); eye.move(to:pt(17,49))
            eye.curve(to:pt(36,38), controlPoint1:pt(23,47), controlPoint2:pt(30,42))
            eye.curve(to:pt(24,31), controlPoint1:pt(35,29), controlPoint2:pt(29,27))
            eye.curve(to:pt(17,49), controlPoint1:pt(20,34), controlPoint2:pt(18,42))
            eye.close(); NSColor.white.setFill(); eye.fill()
            NSColor.black.setStroke(); eye.lineWidth=2.8; eye.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class GuardApp: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var orbWindow: NSPanel!
    var orb: OrbView!
    var item: NSStatusItem!
    var timer: Timer?
    var busy = false
    var failures = 0
    var chinaHits = 0
    var armed = false
    var networkBlocked = false
    var rocketMissingHits = 0
    var blocked: Bool { networkBlocked || rocketMissingHits >= 2 }
    var lastGood: Date?
    var lastAttempt = Date.distantPast
    var lastAction = Date.distantPast
    let state = NSTextField(labelWithString: "请先打开小火箭，再使用 AI 客户端")
    let ip = NSTextField(labelWithString: "出口 IP · 等待检测")
    let region = NSTextField(wrappingLabelWithString: "地区 · 等待检测")
    let detail = NSTextField(wrappingLabelWithString: "启动检测中…")
    let targets = NSTextField(wrappingLabelWithString: "")
    let mode = NSButton(checkboxWithTitle: "异常时自动关闭三个客户端", target: nil, action: nil)
    let ids: Set<String> = ["com.anthropic.claudefordesktop", "com.google.GeminiMacOS", "com.openai.codex"]
    func apps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { ids.contains($0.bundleIdentifier ?? "") || ($0.localizedName ?? "").lowercased() == "codex" }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 405), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "AI 网络守护"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 22), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -22), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22)])
        let title = NSTextField(labelWithString: "◉  AI 网络守护")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        ip.font = .monospacedSystemFont(ofSize: 17, weight: .medium)
        state.font = .systemFont(ofSize: 13, weight: .medium)
        detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor
        targets.font = .systemFont(ofSize: 12); targets.textColor = .secondaryLabelColor
        mode.target = self; mode.action = #selector(toggleMode)
        armed = UserDefaults.standard.bool(forKey: "armed") || CommandLine.arguments.contains("--restore-armed")
        mode.state = armed ? .on : .off
        let row = NSStackView(); row.spacing = 8
        for (name, action) in [("打开小火箭", #selector(openRocket)), ("Ping0 详情", #selector(openPing)), ("立即检测", #selector(check))] {
            row.addArrangedSubview(NSButton(title: name, target: self, action: action))
        }
        let note = NSTextField(wrappingLabelWithString: "小火箭连续 2 次未运行 → 异常\n中国大陆 IP 连续 2 次命中 → 异常\n查询连续失败 2 次 → 状态未知，按保守策略处理\n港澳台不纳入中国大陆规则。纯净度请查看 Ping0。\n仅检查本组件出口，不保证客户端出口一致；不是断网开关。")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        for view in [title, state, ip, region, detail, targets, mode, row, note] { stack.addArrangedSubview(view); view.widthAnchor.constraint(lessThanOrEqualToConstant: 376).isActive = true }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◉ AI"
        let menu = NSMenu()
        for (name, action) in [("显示小组件", #selector(show)), ("立即检测", #selector(check)), ("退出守护（停止保护）", #selector(quit))] {
            let entry = NSMenuItem(title: name, action: action, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
        }
        item.menu = menu
        orbWindow = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        orbWindow.isOpaque = false; orbWindow.backgroundColor = .clear
        orbWindow.hasShadow = true; orbWindow.level = .floating
        orbWindow.hidesOnDeactivate = false
        orbWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        orbWindow.title = "蜘蛛侠悬浮球"
        orb = OrbView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        orb.toggle = { [weak self] in
            guard let self = self else { return }
            if self.window.isVisible { self.window.orderOut(nil) } else { self.show() }
        }
        orb.moved = { [weak self] in self?.positionPanel() }
        orbWindow.contentView = orb
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        orbWindow.setFrameOrigin(NSPoint(x: screen.maxX-110, y: screen.midY))
        orbWindow.orderFrontRegardless()
        assessRocket()
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateTargets()
            self.assessRocket()
            if self.blocked && self.armed { self.closeTargets() }
            if Date().timeIntervalSince(self.lastAttempt) >= 30 { self.check() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
    }
    func positionPanel() {
        guard let orbWindow = orbWindow else { return }
        let screen = orbWindow.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let f = orbWindow.frame
        var x = f.minX-window.frame.width-12
        if x < screen.minX { x = f.maxX+12 }
        x = max(screen.minX, min(x, screen.maxX-window.frame.width))
        let y = max(screen.minY, min(f.maxY-window.frame.height, screen.maxY-window.frame.height))
        window.setFrameOrigin(NSPoint(x:x, y:y))
    }
    func applicationWillTerminate(_ notification: Notification) { UserDefaults.standard.set(armed, forKey: "armed") }
    @objc func show() { positionPanel(); orbWindow?.orderFrontRegardless(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func openPing() { NSWorkspace.shared.open(URL(string: "https://ping0.cc/")!) }
    @objc func openRocket() { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Shadowrocket.app")) }
    @objc func woke() { chinaHits = 0; failures = 0; lastGood = nil; check() }
    @objc func toggleMode() {
        if mode.state == .on {
            let alert = NSAlert(); alert.messageText = "启用自动关闭？"
            alert.informativeText = "连续两次检测到中国大陆 IP 或查询失败，将请求 Claude、Gemini、Codex 退出，3 秒后仍未退出则强制关闭，可能丢失未保存内容，包括当前 Codex 对话。不会注销账号。查询失败也可能只是 Ping0 故障。"
            alert.addButton(withTitle: "启用"); alert.addButton(withTitle: "取消")
            if alert.runModal() != .alertFirstButtonReturn { mode.state = .off; return }
            armed = true
            if blocked { closeTargets() }
        } else { armed = false }
        UserDefaults.standard.set(armed, forKey: "armed")
        check()
    }
    func updateTargets() {
        let names = apps().compactMap(\.localizedName)
        targets.stringValue = "正在运行：" + (names.isEmpty ? "未发现目标客户端" : names.joined(separator: "、"))
    }
    func rocketRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.liguangming.Shadowrocket").contains { !$0.isTerminated }
    }
    func assessRocket() {
        if rocketRunning() {
            rocketMissingHits = 0
        } else {
            rocketMissingHits = min(rocketMissingHits + 1, 2)
            state.stringValue = "⚠ 小火箭未打开（\(rocketMissingHits)/2）"
            state.textColor = .systemRed
            item.button?.title = rocketMissingHits >= 2 ? "⚠ AI" : "◉ AI"
            orb.tint = rocketMissingHits >= 2 ? .systemRed : .systemOrange
            if rocketMissingHits >= 2 {
                if armed { closeTargets() }
                else if Date().timeIntervalSince(lastAction) > 60 { lastAction = Date(); show(); NSSound.beep() }
            }
        }
    }
    @objc func check() {
        guard !busy else { return }
        busy = true; lastAttempt = Date(); updateTargets()
        var request = URLRequest(url: URL(string: "https://ping0.cc/geo")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("curl/8.7.1", forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 12
        let session = URLSession(configuration: config)
        session.dataTask(with: request) { data, response, error in
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 200 && lines.count >= 4 && validIP(lines[0]) && lines[2].hasPrefix("AS")
            DispatchQueue.main.async {
                self.busy = false
                let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                if ok {
                    self.failures = 0; self.lastGood = Date()
                    self.ip.stringValue = "出口 IP · " + lines[0]
                    self.region.stringValue = "地区 · " + lines[1]
                    if mainland(lines[1]) {
                        self.chinaHits += 1; self.networkBlocked = self.chinaHits >= 2
                        self.state.stringValue = "⚠ 中国大陆出口（\(self.chinaHits)/2）"
                        self.state.textColor = .systemRed
                    } else {
                        self.chinaHits = 0; self.networkBlocked = false
                        self.state.stringValue = "● 未命中中国大陆规则 · 纯净度未验证"
                        self.state.textColor = .systemTeal
                    }
                } else {
                    self.chinaHits = 0; self.failures += 1; self.networkBlocked = self.failures >= 2
                    self.state.stringValue = "⚠ 检测失败 · 网络状态未知（\(self.failures)/2）"
                    self.state.textColor = .systemOrange
                    self.ip.stringValue = "出口 IP · 未知"
                    self.region.stringValue = "地区 · 未知（未使用旧结果放行）"
                }
                self.detail.stringValue = "\(time) 检测 · 每 30 秒更新 · " + (self.armed ? "自动关闭已开启" : "仅提醒，不会关闭应用")
                if !self.rocketRunning() {
                    self.state.stringValue = "⚠ 小火箭未打开（\(self.rocketMissingHits)/2）"
                    self.state.textColor = .systemRed
                }
                self.item.button?.title = self.blocked ? "⚠ AI" : "◉ AI"
                self.orb.tint = self.blocked ? .systemRed : ((self.failures > 0 || self.chinaHits > 0) ? .systemOrange : .systemTeal)
                if self.blocked {
                    if self.armed { self.closeTargets() }
                    else if Date().timeIntervalSince(self.lastAction) > 60 { self.lastAction = Date(); self.show(); NSSound.beep() }
                }
            }
            session.finishTasksAndInvalidate()
        }.resume()
    }
    func closeTargets() {
        guard armed && blocked else { return }
        for app in apps() {
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self, self.armed, self.blocked, !app.isTerminated else { return }
                app.forceTerminate()
            }
        }
    }
}
let app = NSApplication.shared
let delegate = GuardApp()
app.delegate = delegate
app.run()
