import AppKit
import SwiftUI

struct WheelItem {
  let title: String
  let icon: String
  let action: String
}
enum WheelActionItems {
  private static func supportsFinovox(_ urls: [URL], preview: Bool) -> Bool {
    guard !urls.contains(where: Family.isFolder) else { return false }
    guard !urls.isEmpty, urls.allSatisfy({ [.pdf, .image, .archive].contains(Family.of($0)) }) else { return false }
    if preview {
      return urls.allSatisfy { FinovoxUploader.extensions.contains($0.pathExtension.lowercased()) }
    }
    return FinovoxUploader.accepts(urls)
  }
  static func forURLs(_ urls: [URL], preview: Bool = false) -> [WheelItem] {
    [
      WheelItem(title: "AIRDROP", icon: "wheel:airdrop", action: "action:airdrop"),
      WheelItem(title: "FLOAT", icon: "wheel:float", action: "action:float"),
      WheelItem(title: "COPY", icon: "wheel:copy", action: "action:copy"),
      WheelItem(title: "MOVE", icon: "wheel:moveto", action: "action:moveto"),
      WheelItem(title: "COPY PATH", icon: "wheel:path", action: "action:path"),
      WheelItem(title: "TERMINAL", icon: "wheel:terminal", action: "action:terminal"),
    ] + (supportsFinovox(urls, preview: preview)
      ? [WheelItem(title: "FINOVOX", icon: "wheel:finovox", action: "action:finovox")] : [])
  }
}
final class WheelPanel: NSPanel {
  var preview = false
  override var canBecomeKey: Bool { preview }
  override var canBecomeMain: Bool { false }
}

/// The window and dragging destination stay alive when a modifier changes the menu.
final class WheelSurface: NSView {
  let wheel: WheelView
  private var material: NSView?
  init(frame: NSRect, files: [URL], items: [WheelItem], preview: Bool) {
    wheel = WheelView(frame: NSRect(origin: .zero, size: frame.size), urls: files, items: items, preview: preview)
    super.init(frame: frame)
    wantsLayer = true
    let background: NSView
    if #available(macOS 26.0, *) {
      background = NSHostingView(rootView: WheelGlass(appearance: wheel.visualState))
    } else {
      let effect = NSVisualEffectView(frame: bounds)
      effect.material = .hudWindow
      effect.blendingMode = .behindWindow
      effect.state = .active
      effect.wantsLayer = true
      effect.layer?.backgroundColor = NSColor(calibratedRed: 192/255, green: 201/255,
        blue: 205/255, alpha: 0.25).cgColor
      background = effect
    }
    background.frame = bounds
    background.autoresizingMask = [.width, .height]
    background.wantsLayer = true
    material = background
    addSubview(background)
    wheel.frame = bounds
    wheel.autoresizingMask = [.width, .height]
    addSubview(wheel)
    update(items)
  }
  required init?(coder: NSCoder) { fatalError() }
  func update(_ items: [WheelItem]) {
    wheel.replaceItems(items)
    if #available(macOS 26.0, *) { /* The hosting view observes the stable selection model. */ }
    else if let material, material is NSVisualEffectView {
      let mask = CAShapeLayer()
      mask.path = WheelGeometry.backdropRingPath(center: NSPoint(x: bounds.midX, y: bounds.midY))
      mask.fillRule = .evenOdd
      material.layer?.mask = mask
    }
  }
}

final class WheelController {
  let state: AppState
  private(set) var panel: WheelPanel?
  private(set) var surface: WheelSurface?
  private(set) var shownMode: String?
  private var panelSession: UInt64?
  private var files: [URL] = []
  private var drag = WheelDragSession(pasteboardGeneration: NSPasteboard(name: .drag).changeCount)
  private var monitors: [Any] = []
  private var observers: [NSObjectProtocol] = []
  private var timer: Timer?
  private var pointer = WheelPointerState()
  private var modifiers = WheelModifierState()
  var acceptsDragFiles: (([URL]) -> Bool)?
  private var pendingClose: DispatchWorkItem?
  private var cachedGeneration = Int.min
  private var cachedURLs: [URL] = []
  var progressPanels: [NSPanel] = []
  var trace: ((String) -> Void)?
  init(state: AppState) { self.state = state }
  func start() {
    guard timer == nil else { return }
    _ = WheelHoverFeedback.shared
    let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
    // Register modifiers separately: a restricted key-down monitor must not disable mouse monitoring.
    for mask: NSEvent.EventTypeMask in [mouseMask, .flagsChanged] {
      if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0) }) { monitors.append(global) }
    }
    if let local = NSEvent.addLocalMonitorForEvents(matching: mouseMask.union([.flagsChanged, .keyDown]), handler: { [weak self] event in
      self?.handle(event)
      return event
    }) { monitors.append(local) }
    // Reconcile with physical state during AppKit tracking loops; key transitions come from events.
    let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.refresh() }
    timer.tolerance = 0.002
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
    observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.cancel() })
    observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.cancel() })
  }
  func stop() {
    timer?.invalidate(); timer = nil
    monitors.forEach { NSEvent.removeMonitor($0) }; monitors.removeAll()
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    observers.removeAll()
    pendingClose?.cancel(); pendingClose = nil
    close()
  }
  deinit { stop() }
  private func handle(_ event: NSEvent) {
    switch event.type {
    case .keyDown:
      if event.keyCode == 53 { cancel() }
    case .leftMouseDown:
      modifiers.mouseChanged(flags: event.modifierFlags)
      if pointer.isNewPress(at: event.timestamp), drag.phase != .idle { refresh(down: false, flags: event.modifierFlags) }
      pointer.event(down: true, at: event.timestamp)
      if panel?.preview == true, panel?.frame.contains(NSEvent.mouseLocation) != true { close() }
      refresh(down: true, flags: event.modifierFlags)
    case .leftMouseDragged:
      modifiers.mouseChanged(flags: event.modifierFlags)
      refresh(down: true, flags: event.modifierFlags)
    case .leftMouseUp:
      modifiers.mouseChanged(flags: event.modifierFlags)
      refresh(down: false, flags: event.modifierFlags)
    case .flagsChanged:
      modifierChanged(flags: event.modifierFlags, keyCode: event.keyCode)
    default: break
    }
  }
  func modifierChanged(flags: NSEvent.ModifierFlags, keyCode: UInt16) {
    modifiers.changed(flags: flags, keyCode: keyCode)
    refresh(flags: flags)
  }
  func matches(_ name: String, _ flags: NSEvent.ModifierFlags) -> Bool {
    let flags = flags.intersection([.shift, .command, .control, .option, .function])
    switch name {
    case "option": return flags == .option
    case "shift": return flags == .shift
    case "command": return flags == .command
    case "control": return flags == .control
    case "fn": return flags == .function
    case "fnShift": return flags == [.function, .shift]
    default: return false
    }
  }
  private func mode(for flags: NSEvent.ModifierFlags) -> String? {
    if matches(state.conversionModifier, flags) { return "formats" }
    if matches(state.toolModifier, flags) { return "tools" }
    if matches(state.actionModifier, flags) { return "actions" }
    return nil
  }
  private func dragURLs(_ pasteboard: NSPasteboard) -> [URL] {
    (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
  }
  func refresh(down overrideDown: Bool? = nil, flags overrideFlags: NSEvent.ModifierFlags? = nil) {
    let time = ProcessInfo.processInfo.systemUptime
    if let overrideDown { pointer.event(down: overrideDown, at: time) }
    let physicalDown = NSEvent.pressedMouseButtons & 1 != 0 || CGEventSource.buttonState(.combinedSessionState, button: .left)
    let down = overrideDown ?? pointer.reconcile(physicalDown: physicalDown, at: time)
    let physicalFn = CGEventSource.keyState(.combinedSessionState, key: 63)
    if overrideFlags == nil { modifiers.reconcile(flags: NSEvent.modifierFlags, physicalFn: physicalFn, at: time) }
    let flags = modifiers.normalized(overrideFlags ?? NSEvent.modifierFlags, physicalFn: physicalFn)
    let pb = NSPasteboard(name: .drag)
    if cachedGeneration != pb.changeCount || (down && cachedURLs.isEmpty) {
      cachedGeneration = pb.changeCount
      cachedURLs = dragURLs(pb)
    }
    let resolve: (NSEvent.ModifierFlags) -> String? = { self.mode(for: $0) }
    let cancelled = !state.wheelEnabled || (down && CGEventSource.keyState(.combinedSessionState, key: 53))
    let oldPhase = drag.phase, oldMode = drag.mode
    let change = drag.sample(down: down, flags: flags,
      generation: pb.changeCount, containsFiles: !cachedURLs.isEmpty && acceptsDragFiles?(cachedURLs) != false, cancelled: cancelled, resolve: resolve)
    if drag.phase != oldPhase || drag.mode != oldMode {
      trace?("session=\(drag.id) phase=\(drag.phase) mode=\(drag.mode ?? "none")")
    }
    if change.close { close() }
    if change.began {
      pendingClose?.cancel(); pendingClose = nil
      files = cachedURLs
    }
    if let mode = drag.mode, drag.phase == .dragging, shownMode != mode || panelSession != drag.id {
      present(files, mode: mode, session: drag.id)
    }
    if let panel, panelSession == drag.id, drag.phase == .dragging {
      surface?.wheel.hover(at: surface!.wheel.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }
    if change.released {
      let id = drag.id
      let cleanup = DispatchWorkItem { [weak self] in
        guard let self, self.drag.finish(id: id, generation: NSPasteboard(name: .drag).changeCount) else { return }
        if self.panelSession == id { self.close() }
      }
      pendingClose?.cancel(); pendingClose = cleanup
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: cleanup)
    }
  }
  private func refreshNativeDrag() {
    if drag.phase == .dragging { refresh(down: true) } else { refresh() }
  }
  private func cancel() {
    _ = drag.sample(down: pointer.isDown || NSEvent.pressedMouseButtons & 1 != 0, flags: NSEvent.modifierFlags,
      generation: NSPasteboard(name: .drag).changeCount, containsFiles: false, cancelled: true, resolve: { _ in nil })
    pendingClose?.cancel(); pendingClose = nil
    close()
  }
  func close() {
    if let panel {
      panel.orderOut(nil)
      DispatchQueue.main.async { panel.close() }
    }
    panel = nil; surface = nil; panelSession = nil; shownMode = nil
  }
  func showProgress(_ job: Job) {
    let progress = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: 150),
      styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
    progress.title = job.title
    progress.level = .floating
    progress.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    progress.hidesOnDeactivate = false
    progress.isReleasedWhenClosed = false
    progress.contentView = NSHostingView(rootView: WheelProgress(state: state, id: job.id, onDismiss: { [weak self, weak progress] in
      guard let progress else { return }
      progress.close()
      self?.progressPanels.removeAll { $0 === progress }
    }))
    progress.center(); progress.orderFrontRegardless()
    progressPanels.removeAll { !$0.isVisible }; progressPanels.append(progress)
  }
  private func items(_ urls: [URL], mode: String) -> [WheelItem] {
    switch mode {
    case "formats": return Compatibility.targets(urls).map {
      WheelItem(title: Compatibility.label($0), icon: "", action: "convert:" + $0)
    }
    case "tools": return Tool.available(urls).map {
      WheelItem(title: $0.id == "mergepdf" && Family.of(urls[0]) == .image ? "CREATE PDF" : $0.wheelTitle, icon: WheelGlyph.key($0.id, family: Family.of(urls[0])), action: $0.id)
    }
    default: return WheelActionItems.forURLs(urls)
    }
  }
  // Menu preview has explicit click semantics; an actual drag only commits through AppKit's drop callback.
  func show(_ urls: [URL], mode: String) { present(urls, mode: mode, session: nil) }
  private func present(_ urls: [URL], mode: String, session: UInt64?) {
    guard !urls.isEmpty else { return }
    let choices = items(urls, mode: mode)
    if let surface, let panel, panelSession == session, surface.wheel.urls == urls {
      shownMode = mode
      surface.wheel.emptyText = mode == "tools" ? "No tools" : "No conversions"
      surface.update(choices)
      trace?("update mode=\(mode) window=\(panel.windowNumber)")
      return
    }
    close()
    let side = WheelGeometry.side
    let point = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
    let origin = WheelGeometry.origin(around: point, in: screen.visibleFrame)
    let panel = WheelPanel(contentRect: NSRect(origin: origin, size: NSSize(width: side, height: side)),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.preview = session == nil
    // Keep native drag feedback above the wheel. Raising this panel above the
    // system dragging level also covers other drag UI and breaks its layering.
    panel.level = .popUpMenu
    // The glass disc draws its own circular shadow. A window shadow follows the
    // panel's square bounds and leaves a gray edge below the transparent wheel.
    panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    let surface = WheelSurface(frame: NSRect(x: 0, y: 0, width: side, height: side), files: urls,
      items: choices, preview: session == nil)
    surface.appearance = ClementineAppearance(rawValue: state.appearance)?.nsAppearance
    surface.wheel.emptyText = mode == "tools" ? "No tools" : "No conversions"
    surface.wheel.onRefresh = { [weak self] in if session != nil { self?.refreshNativeDrag() } }
    surface.wheel.onValidate = { [weak self] info in
      guard let self else { return false }
      guard self.dragURLs(info.draggingPasteboard) == urls else { return false }
      if let session { return self.drag.acceptsDrop(id: session, generation: info.draggingPasteboard.changeCount) }
      return self.panel?.preview == true
    }
    surface.wheel.onChoose = { [weak self] item, inputs, generation in
      guard let self else { return false }
      if let session {
        guard let generation, self.drag.commit(id: session, generation: generation) else { return false }
      } else { guard self.panel?.preview == true else { return false } }
      self.trace?("commit action=\(item.action) session=\(session.map(String.init) ?? "preview")")
      self.pendingClose?.cancel(); self.pendingClose = nil
      self.close()
      DispatchQueue.main.async {
        if item.action.hasPrefix("action:") { self.state.fileAction(String(item.action.dropFirst(7)), urls: inputs) }
        else if item.action.hasPrefix("convert:") {
          let previousJob = self.state.jobs.first?.id
          self.state.submit(item.action, files: inputs)
          if let job = self.state.jobs.first, job.id != previousJob { self.showProgress(job) }
        } else { self.state.add(inputs, replace: true); self.state.configure(item.action) }
      }
      return true
    }
    surface.wheel.onHoverFeedback = { [weak self] in
      guard let self else { return }
      WheelHoverFeedback.shared.perform(sound: self.state.sound, haptic: self.state.haptics)
    }
    surface.wheel.onDismiss = { [weak self] in self?.cancel() }
    surface.wheel.onEnd = { [weak self] in
      guard let self, let session, self.drag.id == session,
        self.drag.phase == .dragging || self.drag.phase == .ending else { return }
      self.cancel()
    }
    panel.contentView = surface
    self.panel = panel; self.surface = surface; self.panelSession = session; self.shownMode = mode
    panel.orderFrontRegardless()
    // Petals bloom independently from the pointer-centred disc. The panel and
    // its native drop geometry remain stable throughout the animation.
    surface.wheel.beginOpening()
    trace?("show mode=\(mode) window=\(panel.windowNumber)")
    if session == nil && NSApp.isActive { panel.makeKey(); panel.makeFirstResponder(surface.wheel) }
  }
}
final class WheelView: NSView {
  let urls: [URL], preview: Bool
  private(set) var items: [WheelItem]
  var onChoose: ((WheelItem, [URL], Int?) -> Bool)?
  var onValidate: ((NSDraggingInfo) -> Bool)?
  var onRefresh: (() -> Void)?
  var onEnd: (() -> Void)?
  var onDismiss: (() -> Void)?
  var onSelectionChange: ((Int?) -> Void)?
  var onHoverFeedback: (() -> Void)?
  private var feedbackGate = WheelFeedbackGate()
  var previewDefaultSelection: Int?
  var allowsPointerInteraction = true {
    didSet {
      guard oldValue != allowsPointerInteraction else { return }
      if preview && !allowsPointerInteraction { pressed = nil }
      updateTrackingAreas()
    }
  }
  var previewLabel: String?
  var showsIdleCenter = true
  var emptyText = "No tools"
  private(set) var selected: Int?
  private var pressed: Int?
  private var consumed = false
  private var nativeSequence: Int?
  private var tracking: NSTrackingArea?
  private var openingTimer: Timer?
  private var hoverTimer: Timer?
  private var openingProgress: CGFloat = 1
  let visualState: WheelAppearance
  private var fileSizeText = "…"
  var center: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }
  init(frame: NSRect, urls: [URL], items: [WheelItem], preview: Bool = true) {
    self.urls = urls; self.items = items; self.preview = preview
    visualState = WheelAppearance(items: items, opened: preview)
    super.init(frame: frame)
    registerForDraggedTypes([.fileURL])
    setAccessibilityElement(true); setAccessibilityRole(.group)
    replaceItems(items)
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let size = urls.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
      let label = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
      DispatchQueue.main.async { [weak self] in
        self?.fileSizeText = label; self?.needsDisplay = true
      }
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit { openingTimer?.invalidate();hoverTimer?.invalidate() }
  func beginOpening() {
    openingTimer?.invalidate()
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      openingProgress = 1; visualState.opening = 1; needsDisplay = true; return
    }
    let started = ProcessInfo.processInfo.systemUptime
    openingProgress = 0; visualState.opening = 0; needsDisplay = true
    let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
      guard let self else { timer.invalidate(); return }
      let elapsed = ProcessInfo.processInfo.systemUptime - started
      self.openingProgress = min(1, CGFloat(elapsed / 0.34))
      self.visualState.opening = self.openingProgress
      self.needsDisplay = true
      if self.openingProgress >= 1 { timer.invalidate(); self.openingTimer = nil }
    }
    timer.tolerance = 0.001
    RunLoop.main.add(timer, forMode: .common)
    openingTimer = timer
  }
  override var acceptsFirstResponder: Bool { preview && allowsPointerInteraction }
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard !preview || allowsPointerInteraction else { return nil }
    return super.hitTest(point)
  }
  func replaceItems(_ items: [WheelItem]) {
    self.items = items
    feedbackGate = WheelFeedbackGate()
    hoverTimer?.invalidate();hoverTimer=nil
    selected=nil;visualState.selected=nil
    visualState.count=items.count;visualState.hoverLevels=Array(repeating:0,count:items.count)
    visualState.hasIcons = items.contains { !$0.icon.isEmpty };pressed=nil
    setAccessibilityLabel("Roue Clémentine : " + items.map(\.title).joined(separator: ", "))
    needsDisplay = true
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking); self.tracking = nil }
    guard !preview || allowsPointerInteraction else { return }
    let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil)
    tracking = area; addTrackingArea(area)
  }
  func index(_ point: NSPoint) -> Int? { WheelGeometry.hit(point, count: items.count, center: center) }
  func hover(at point: NSPoint) {
    guard !preview || allowsPointerInteraction else { return }
    let next = index(point)
    select(next)
  }
  private func select(_ next: Int?) {
    guard next != selected else { return }
    selected=next;visualState.selected=next;animateHover(to:next);onSelectionChange?(next)
    if feedbackGate.selectionChanged(to: next.map { items[$0].action }, at: ProcessInfo.processInfo.systemUptime) {
      onHoverFeedback?()
    }
  }
  /// Drives the catalogue/onboarding preview without changing live drag behaviour.
  func setPreviewSelection(_ index: Int?) {
    guard preview else { return }
    let safe = index.flatMap { items.indices.contains($0) ? $0 : nil }
    select(safe)
  }
  private func animateHover(to target:Int?) {
    hoverTimer?.invalidate();hoverTimer=nil
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      visualState.hoverLevels=items.indices.map {$0 == target ? 1 : 0};needsDisplay=true;return
    }
    if visualState.hoverLevels.count != items.count {visualState.hoverLevels=Array(repeating:0,count:items.count)}
    var last=ProcessInfo.processInfo.systemUptime
    let timer=Timer(timeInterval:1.0/120.0,repeats:true) {[weak self] timer in
      guard let self else {timer.invalidate();return}
      let now=ProcessInfo.processInfo.systemUptime,dt=max(0,min(0.04,now-last));last=now
      var levels=self.visualState.hoverLevels,active=false
      for i in levels.indices {
        let destination:CGFloat=i == target ? 1 : 0
        let duration=destination > levels[i] ? 0.16 : 0.10
        let step=CGFloat(dt/duration)
        if abs(levels[i]-destination)<=step {levels[i]=destination}
        else {levels[i]+=levels[i]<destination ? step : -step;active=true}
      }
      self.visualState.hoverLevels=levels;self.needsDisplay=true
      if !active {timer.invalidate();self.hoverTimer=nil}
    }
    timer.tolerance=0.001;RunLoop.main.add(timer,forMode:.common);hoverTimer=timer
  }
  override func mouseMoved(with event: NSEvent) { hover(at: convert(event.locationInWindow, from: nil)) }
  override func mouseEntered(with event: NSEvent) { hover(at: convert(event.locationInWindow, from: nil)) }
  override func mouseExited(with event: NSEvent) {
    guard !preview || allowsPointerInteraction else { return }
    select(previewDefaultSelection)
  }
  override func mouseDown(with event: NSEvent) {
    guard preview, allowsPointerInteraction, !consumed else { return }
    pressed = index(convert(event.locationInWindow, from: nil))
  }
  override func mouseUp(with event: NSEvent) {
    guard preview, allowsPointerInteraction, !consumed, nativeSequence == nil else { return }
    let slot = index(convert(event.locationInWindow, from: nil))
    defer { pressed = nil }
    guard let slot, slot == pressed else { return }
    consumed = onChoose?(items[slot], urls, nil) == true
  }
  override func cancelOperation(_ sender: Any?) { onDismiss?() }
  override func keyDown(with event: NSEvent) {
    guard preview, allowsPointerInteraction else { return }
    if event.keyCode == 53 { onDismiss?(); return }
    if event.keyCode == 36, let selected, !consumed {
      consumed = onChoose?(items[selected], urls, nil) == true
    } else if [123, 124, 125, 126].contains(event.keyCode), !items.isEmpty {
      let delta = event.keyCode == 123 || event.keyCode == 126 ? -1 : 1
      select(((selected ?? (delta > 0 ? -1 : 0)) + delta + items.count) % items.count)
    } else { super.keyDown(with: event) }
  }
  override func wantsPeriodicDraggingUpdates() -> Bool { true }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
  private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
    onRefresh?()
    guard !consumed, onValidate?(sender) != false,
      nativeSequence == nil || nativeSequence == sender.draggingSequenceNumber else {
      select(nil); return []
    }
    nativeSequence = sender.draggingSequenceNumber
    hover(at: convert(sender.draggingLocation, from: nil))
    guard selected != nil else { return [] }
    return WheelGeometry.operation(allowed: sender.draggingSourceOperationMask)
  }
  override func draggingExited(_ sender: NSDraggingInfo?) { select(nil) }
  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    !update(sender).isEmpty && selected != nil
  }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard !update(sender).isEmpty, let slot = selected else { return false }
    guard let files = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty else { return false }
    consumed = onChoose?(items[slot], files, sender.draggingPasteboard.changeCount) == true
    return consumed
  }
  override func draggingEnded(_ sender: NSDraggingInfo) {
    guard nativeSequence == sender.draggingSequenceNumber else { return }
    if !consumed { onEnd?() }
    nativeSequence = nil
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    if items.isEmpty {
      let message = NSRect(x: center.x - 94, y: center.y - 26, width: 188, height: 52)
      NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
      NSBezierPath(roundedRect: message, xRadius: 18, yRadius: 18).fill()
      let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
      (emptyText as NSString).draw(in: message.insetBy(dx: 8, dy: 16), withAttributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
      return
    }
    func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
      let font = NSFont.systemFont(ofSize:size,weight:weight)
      return NSFont(descriptor:font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor,size:size) ?? font
    }
    let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let petalColors: [NSColor] = {
      if dark {
        return [NSColor(calibratedRed: 0.29, green: 0.285, blue: 0.275, alpha: 0.96),
                NSColor(calibratedRed: 0.245, green: 0.24, blue: 0.23, alpha: 0.96),
                NSColor(calibratedRed: 0.215, green: 0.21, blue: 0.20, alpha: 0.97)]
      }
      return [NSColor(calibratedWhite: 1, alpha: 0.80),
              NSColor(calibratedRed: 243/255, green: 246/255, blue: 247/255, alpha: 0.58),
              NSColor(calibratedRed: 244/255, green: 246/255, blue: 246/255, alpha: 0.75)]
    }()
    for (i, item) in items.enumerated() {
      let phase = WheelGeometry.flowerProgress(openingProgress, index: i, count: items.count)
      let rawHover=i < visualState.hoverLevels.count ? visualState.hoverLevels[i] : 0
      let hover=rawHover*rawHover*(3-2*rawHover)
      var transform = WheelGeometry.flowerTransform(progress: openingProgress, index: i, count: items.count, center: center)
      let basePath = WheelGeometry.petal(i,count:items.count,center:center)
      let path = basePath.copy(using: &transform) ?? basePath
      context.saveGState(); context.setAlpha(phase)
      context.saveGState();context.addPath(path);context.clip()
      let colors = petalColors.map(\.cgColor) as CFArray
      if let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.68,1]) {
        context.drawRadialGradient(gradient,startCenter:center,startRadius:0,endCenter:center,endRadius:WheelGeometry.backdrop,options:[.drawsAfterEndLocation])
      };context.restoreGState()
      if hover>0 {
        context.saveGState();context.setAlpha(hover);context.addPath(path)
        context.setFillColor(NSColor(hex:"FF5200").cgColor);context.fillPath();context.restoreGState()
      }
      context.addPath(path)
      let idleStroke = dark
        ? NSColor.white.withAlphaComponent(0.11)
        : NSColor(calibratedRed: 93/255, green: 102/255, blue: 102/255, alpha: 0.22)
      let activeStroke=NSColor(hex:"C26534").withAlphaComponent(0.44)
      context.setStrokeColor((idleStroke.blended(withFraction:hover,of:activeStroke) ?? activeStroke).cgColor)
      context.setLineWidth(0.75);context.strokePath()
      let a = WheelGeometry.angle(i,count:items.count)
      let pos=WheelGeometry.point(30 + 54.5312 * Double(phase),a,center:center)
      let idleColor: NSColor = dark ? .white : .black
      let color=idleColor.blended(withFraction:hover,of:.white) ?? idleColor
      if !item.icon.isEmpty { WheelGlyph.draw(item.icon,in:CGRect(x:pos.x-9,y:pos.y-1.5,width:18,height:18),color:color,context:context) }
      WheelGlyph.text(item.title,centeredAt:CGPoint(x:pos.x,y:pos.y-(item.icon.isEmpty ? 0 : 10.5)),font:rounded(item.icon.isEmpty ? 12.5 : 8.5,.semibold),color:color,tracking:item.icon.isEmpty ? 0.25 : 0.2)
      context.restoreGState()
    }
    // Reveal one perfectly circular hub. This removes the overlapping inner
    // borders of adjacent petals while preserving the material below them.
    context.saveGState()
    context.setBlendMode(.clear)
    let hubRadius = WheelGeometry.hubHole
    context.fillEllipse(in: CGRect(x: center.x-hubRadius, y: center.y-hubRadius,
      width: hubRadius*2, height: hubRadius*2))
    context.restoreGState()
    guard selected != nil || showsIdleCenter else { return }
    let label=selected.map { items[$0].title } ?? previewLabel ?? fileSizeText
    let toolLabel=visualState.hasIcons && selected != nil
    let height=visualState.centerHeight
    let pill=CGRect(x:center.x-35,y:center.y-height/2,width:70,height:height)
    let pillRadius = height / 2
    let pillPath = NSBezierPath(roundedRect: pill, xRadius: pillRadius, yRadius: pillRadius)
    let centerPhase = max(0, min(1, (openingProgress - 0.32) / 0.68))
    context.saveGState(); context.setAlpha(centerPhase)
    context.setShadow(offset: CGSize(width: 0, height: -2), blur: 6,
      color: NSColor.black.withAlphaComponent(dark ? 0.10 : 0.063).cgColor)
    let hubColor = dark
      ? NSColor(calibratedRed: 0.235, green: 0.23, blue: 0.22, alpha: 0.98)
      : NSColor.white.withAlphaComponent(0.98)
    hubColor.setFill()
    pillPath.fill();context.restoreGState()
    (dark ? NSColor.white.withAlphaComponent(0.13) : NSColor.white.withAlphaComponent(0.70)).setStroke()
    let borderRect = pill.insetBy(dx: 0.5, dy: 0.5)
    let border = NSBezierPath(roundedRect: borderRect,
      xRadius: borderRect.height / 2, yRadius: borderRect.height / 2)
    border.lineWidth=1;border.stroke()
    let lines = label.components(separatedBy: "\n")
    if lines.count == 2 {
      let font = rounded(7.5, .medium), color = dark ? NSColor.white : NSColor.black
      WheelGlyph.text(lines[0], centeredAt: CGPoint(x:center.x,y:center.y+4.4),
        font:font,color:color,tracking:0.1)
      WheelGlyph.text(lines[1], centeredAt: CGPoint(x:center.x,y:center.y-4.4),
        font:font,color:color,tracking:0.1)
    } else {
      WheelGlyph.text(label,centeredAt:center,font:rounded(toolLabel ? 8.5 : 11.5,toolLabel ? .semibold : .medium),color:dark ? .white : .black,tracking:toolLabel ? 0.2 : 0.25)
    }

  }
}

struct WheelProgress: View {
  @ObservedObject var state: AppState
  let id: UUID
  let onDismiss: () -> Void
  var body: some View {
    if let job = state.jobs.first(where: { $0.id == id }) {
      VStack(alignment: .leading, spacing: 12) {
        Text(job.files.count == 1 ? job.files[0].lastPathComponent : "\(job.files.count) fichiers").font(.headline).lineLimit(1)
        if !job.done { ProgressView(value: job.progress).tint(citrus) }
        Text(job.state).font(.caption).foregroundStyle(job.failed ? .red : .secondary).lineLimit(3)
        HStack {
          Spacer()
          if !job.done { Button("Annuler") { state.cancel(id) } }
        }
      }.padding(18).frame(width: 330, height: 150)
        .onAppear { if job.done { onDismiss() } }
        .onChange(of: job.done) { _, done in if done { onDismiss() } }
    }
  }
}
