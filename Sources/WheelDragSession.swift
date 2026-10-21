import AppKit

/// One identity per physical gesture. Native drop callbacks and deferred cleanup must carry it.
struct WheelDragSession {
  enum Phase: Equatable { case idle, pressed, dragging, ending, blocked }
  struct Change {
    var began = false
    var released = false
    var close = false
  }
  private(set) var phase: Phase = .idle
  private(set) var id: UInt64 = 0
  private(set) var pasteboardGeneration: Int?
  private(set) var mode: String?
  private var idleGeneration: Int
  private var baseline: Int
  private var shortcut = WheelGesture()
  init(pasteboardGeneration: Int) {
    idleGeneration = pasteboardGeneration
    baseline = pasteboardGeneration
  }
  mutating func sample(down: Bool, flags: NSEvent.ModifierFlags, generation: Int,
                       containsFiles: Bool, cancelled: Bool = false,
                       resolve: (NSEvent.ModifierFlags) -> String?) -> Change {
    var change = Change()
    if cancelled {
      change.close = phase == .dragging || phase == .ending
      phase = down ? .blocked : .idle
      mode = nil
      pasteboardGeneration = nil
      _ = shortcut.update(dragging: false, flags: flags, cancelled: true, resolve: resolve)
      if !down { idleGeneration = generation }
      return change
    }
    if !down {
      switch phase {
      case .dragging:
        phase = .ending
        idleGeneration = generation
        change.released = true
      case .ending: break // AppKit may deliver performDragOperation after the mouse-up monitor.
      default:
        phase = .idle
        mode = nil
        idleGeneration = generation
        pasteboardGeneration = nil
        _ = shortcut.update(dragging: false, flags: flags, resolve: resolve)
      }
      return change
    }
    if phase == .blocked { return change }
    if phase == .idle || phase == .ending {
      change.close = phase == .ending
      id &+= 1
      baseline = idleGeneration
      pasteboardGeneration = nil
      phase = .pressed
      mode = nil
      _ = shortcut.update(dragging: false, flags: flags, resolve: resolve)
    }
    // A mouse click or a window move must never reuse the previous drag's file URLs.
    if phase == .pressed, generation != baseline, containsFiles {
      phase = .dragging
      pasteboardGeneration = generation
      change.began = true
    }
    if phase == .dragging {
      mode = shortcut.update(dragging: true, flags: flags, resolve: resolve)
    }
    return change
  }
  func acceptsDrop(id candidate: UInt64, generation: Int) -> Bool {
    candidate == id && pasteboardGeneration == generation && (phase == .dragging || phase == .ending)
  }
  mutating func commit(id candidate: UInt64, generation: Int) -> Bool {
    guard acceptsDrop(id: candidate, generation: generation) else { return false }
    phase = phase == .ending ? .idle : .blocked
    idleGeneration = generation
    pasteboardGeneration = nil
    mode = nil
    return true
  }
  @discardableResult mutating func finish(id candidate: UInt64, generation: Int) -> Bool {
    guard candidate == id, phase == .ending else { return false }
    phase = .idle
    mode = nil
    pasteboardGeneration = nil
    idleGeneration = generation
    _ = shortcut.update(dragging: false, flags: [], resolve: { _ in nil })
    return true
  }
}

/// Assigning an occupied key swaps the two wheels instead of leaving an unreachable shortcut.
enum WheelShortcutAssignments {
  static let roles = ["formats", "tools", "actions"]
  static let choices = ["option", "fn", "shift", "command", "control", "fnShift", "none"]
  static let defaults = ["formats": "shift", "tools": "option", "actions": "command"]
  static let commandOptionMigrationKey = "didSwapToolActionModifiers20261021"
  static func migrateCommandOption(in preferences:UserDefaults) {
    guard !preferences.bool(forKey:commandOptionMigrationKey) else {return}
    for key in ["conversionModifier","toolModifier","actionModifier"] {
      guard let old=preferences.string(forKey:key) else {continue}
      if old == "command" {preferences.set("option",forKey:key)}
      else if old == "option" {preferences.set("command",forKey:key)}
    }
    preferences.set(true,forKey:commandOptionMigrationKey)
  }
  static func symbol(_ name: String) -> String {
    ["option":"⌥", "fn":"fn", "shift":"⇧", "command":"⌘", "control":"⌃", "fnShift":"fn ⇧", "none":"—"][name] ?? "—"
  }
  static func normalized(_ values: [String: String]) -> [String: String] {
    var result: [String: String] = [:]
    var used = Set<String>()
    for role in roles {
      var value = values[role] ?? defaults[role]!
      if !choices.contains(value) || (value != "none" && used.contains(value)) {
        value = choices.first { $0 != "none" && !used.contains($0) } ?? "none"
      }
      result[role] = value
      if value != "none" { used.insert(value) }
    }
    return result
  }
  static func assigning(_ value: String, to role: String, in values: [String: String]) -> [String: String] {
    var result = normalized(values)
    guard roles.contains(role), choices.contains(value) else { return result }
    let previous = result[role]!
    for other in roles where other != role && value != "none" && result[other] == value { result[other] = previous }
    result[role] = value
    return result
  }
}

/// Event evidence wins over a transient negative physical-state read during native tracking.
struct WheelPointerState {
  private(set) var isDown = false
  private(set) var downSince: Double?
  private var lastEvidence = -Double.infinity
  private var negativeSince: Double?
  private var lastRelease = -Double.infinity
  func isNewPress(at time: Double) -> Bool { !isDown || time > (downSince ?? time) + 0.001 }
  mutating func event(down: Bool, at time: Double) {
    if down && !isDown { downSince = time }
    if !down { downSince = nil; lastRelease = time }
    isDown = down
    lastEvidence = time
    negativeSince = nil
  }
  mutating func reconcile(physicalDown: Bool, at time: Double) -> Bool {
    if physicalDown {
      if !isDown && time - lastRelease < 0.12 { return false }
      event(down: true, at: time); return true
    }
    guard isDown else { return false }
    if negativeSince == nil { negativeSince = time }
    if time - lastEvidence > 0.12, time - negativeSince! > 0.12 { isDown = false; downSince = nil }
    return isDown
  }
}

struct WheelModifierState {
  private(set) var functionHeld = false
  private var missingSince: Double?
  mutating func changed(flags: NSEvent.ModifierFlags, keyCode: UInt16) {
    if keyCode == 63 { functionHeld = flags.contains(.function); missingSince = nil }
  }
  mutating func mouseChanged(flags: NSEvent.ModifierFlags) {
    functionHeld = flags.contains(.function)
    missingSince = nil
  }
  mutating func reconcile(flags: NSEvent.ModifierFlags, physicalFn: Bool, at time: Double) {
    if functionHeld && !flags.contains(.function) && !physicalFn {
      if missingSince == nil { missingSince = time }
      if time - missingSince! > 0.12 { functionHeld = false; missingSince = nil }
    } else { missingSince = nil }
  }
  func normalized(_ flags: NSEvent.ModifierFlags, physicalFn: Bool) -> NSEvent.ModifierFlags {
    var result = flags.intersection([.shift, .command, .control, .option])
    if functionHeld || physicalFn { result.insert(.function) }
    return result
  }
}
