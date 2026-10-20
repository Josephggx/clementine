import AppKit
import Foundation
var assertions = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  assertions += 1
  if !value() { fatalError(message) }
}
func resolve(_ flags: NSEvent.ModifierFlags) -> String? {
  let relevant = flags.intersection([.shift, .command, .control, .option, .function])
  switch relevant {
  case .option, .shift, .function: return "formats"
  case .command: return "tools"
  case .control: return "actions"
  default: return nil
  }
}
func sample(_ state: inout WheelDragSession, _ down: Bool, _ flags: NSEvent.ModifierFlags, _ generation: Int, files: Bool = true, cancelled: Bool = false) -> WheelDragSession.Change {
  state.sample(down: down, flags: flags, generation: generation, containsFiles: files, cancelled: cancelled, resolve: resolve)
}
let allFlags: [NSEvent.ModifierFlags] = (0..<32).map { value in
  var flags: NSEvent.ModifierFlags = []
  if value & 1 != 0 { flags.insert(.shift) }; if value & 2 != 0 { flags.insert(.command) }
  if value & 4 != 0 { flags.insert(.control) }; if value & 8 != 0 { flags.insert(.option) }
  if value & 16 != 0 { flags.insert(.function) }
  return flags
}
// Exhaust all five-step modifier sequences. Reference: latch only on a new key press,
// preserving the wheel on releases and on ambiguous chords.
for initial in allFlags {
  for second in allFlags {
    for third in allFlags {
      for fourth in allFlags {
        var state = WheelDragSession(pasteboardGeneration: 10)
        _ = sample(&state, false, initial, 10)
        _ = sample(&state, true, initial, 10)
        check(state.mode == nil, "An ordinary click cannot open a wheel")
        let begin = sample(&state, true, initial, 11)
        check(begin.began && state.phase == .dragging, "Fresh file drag begins")
        let identity = state.id
        var expected = resolve(initial)
        var previous = initial
        for flags in [second, third, fourth, NSEvent.ModifierFlags()] {
          if !flags.subtracting(previous).isEmpty, let next = resolve(flags) { expected = next }
          _ = sample(&state, true, flags, 11)
          check(state.mode == expected, "Modifier latch differs from reference")
          check(state.id == identity, "Switching modes must retain gesture identity")
          previous = flags
        }
        check(!state.acceptsDrop(id: identity + 1, generation: 11), "Reject obsolete callback")
        check(!state.acceptsDrop(id: identity, generation: 12), "Reject a different pasteboard")
        check(state.commit(id: identity, generation: 11), "First native commit")
        check(!state.commit(id: identity, generation: 11), "Never execute the drop twice")
        _ = sample(&state, true, .control, 11)
        check(state.mode == nil && state.phase == .blocked, "Committed gesture stays suppressed until release")
        _ = sample(&state, false, [], 11)
        _ = sample(&state, true, .shift, 11)
        check(state.mode == nil && state.phase == .pressed, "The next ordinary click cannot reuse files")
      }
    }
  }
}
for flags in allFlags {
  var state = WheelDragSession(pasteboardGeneration: 100)
  _ = sample(&state, true, flags, 100, files: false)
  _ = sample(&state, true, flags, 101, files: false)
  check(state.phase == .pressed, "Do not open until URLs become available")
  check(sample(&state, true, flags, 101).began, "Support delayed pasteboard data")
  let first = state.id
  check(sample(&state, false, [], 101).released, "Mouse up enters native drop grace period")
  check(state.acceptsDrop(id: first, generation: 101), "Native drop may arrive after mouse up")
  _ = sample(&state, true, .shift, 101)
  check(state.phase == .pressed && state.mode == nil, "Fast click after release must not reopen stale data")
  _ = sample(&state, true, .shift, 102)
  let second = state.id
  check(second != first, "New drag has a different identity")
  check(!state.finish(id: first, generation: 102), "Delayed close cannot close next drag")
  check(!state.commit(id: first, generation: 101), "Delayed drop cannot execute in next drag")
  _ = sample(&state, true, flags, 102, cancelled: true)
  check(state.phase == .blocked && state.mode == nil, "Escape cancels")
  for next in allFlags { _ = sample(&state, true, next, 102); check(state.mode == nil, "Escape holds until button release") }
  _ = sample(&state, false, [], 102)
  _ = sample(&state, true, .control, 103)
  check(state.mode == "actions", "Fresh gesture works after cancellation")
}
for flags in allFlags {
  var state = WheelDragSession(pasteboardGeneration: 1)
  _ = sample(&state, true, flags, 2)
  let identity = state.id
  _ = sample(&state, false, flags, 2)
  check(state.commit(id: identity, generation: 2), "A valid late drop succeeds")
  check(!state.finish(id: identity, generation: 2), "Cleanup after committed drop is inert")
  check(!state.commit(id: identity, generation: 2), "Late callbacks are idempotent")
}
// Negative monitor coordinates and small displays must not shift the wheel between modes.
for screen in [NSRect(x: -1920, y: -400, width: 1920, height: 1080), NSRect(x: 0, y: 0, width: 1512, height: 944), NSRect(x: 100, y: 50, width: 200, height: 200)] {
  for point in [screen.origin, NSPoint(x: screen.maxX, y: screen.maxY), NSPoint(x: screen.midX, y: screen.midY)] {
    let origin = WheelGeometry.origin(around: point, in: screen)
    check(origin.x >= screen.minX && origin.y >= screen.minY, "Screen origin bounds")
    check(origin.x + 272 <= screen.maxX || screen.width < 272, "Horizontal bounds")
    check(origin.y + 272 <= screen.maxY || screen.height < 272, "Vertical bounds")
  }
}
for bits in 0..<64 {
  let mask = NSDragOperation(rawValue: UInt(bits))
  let operation = WheelGeometry.operation(allowed: mask)
  check(!operation.contains(.move) && !operation.contains(.delete), "Never tell the source to remove an original")
  check(operation.isEmpty || mask.contains(operation), "Respect the native source mask")
}
for a in WheelShortcutAssignments.choices {
  for b in WheelShortcutAssignments.choices {
    for c in WheelShortcutAssignments.choices {
      let initial = ["formats": a, "tools": b, "actions": c]
      let normalized = WheelShortcutAssignments.normalized(initial)
      let active = normalized.values.filter { $0 != "none" }
      check(Set(active).count == active.count, "Normalize overlapping keys")
      check(WheelShortcutAssignments.normalized(normalized) == normalized, "Stable preference migration")
      for role in WheelShortcutAssignments.roles {
        for value in WheelShortcutAssignments.choices {
          let next = WheelShortcutAssignments.assigning(value, to: role, in: initial)
          check(next[role] == value, "Apply chosen key")
          let assigned = next.values.filter { $0 != "none" }
          check(Set(assigned).count == assigned.count, "No wheel may become inaccessible")
        }
      }
    }
  }
}
var pointer = WheelPointerState()
pointer.event(down: true, at: 1)
for step in 1...100 {
  let time = 1 + Double(step) / 1000
  check(pointer.reconcile(physicalDown: false, at: time), "No false release during initial drag tracking")
}
check(!pointer.isNewPress(at: 0.999), "A late global mouse-down is still the same gesture")
check(pointer.isNewPress(at: 1.1), "A genuinely new mouse press starts a new gesture")
for step in 1...100 {
  let time = 1.1 + Double(step) / 100
  pointer.event(down: true, at: time)
  check(pointer.reconcile(physicalDown: false, at: time + 0.005), "Dragging events bridge native tracking gaps")
}
pointer.event(down: false, at: 3)
check(!pointer.reconcile(physicalDown: false, at: 3), "Explicit mouse up ends immediately")
check(!pointer.reconcile(physicalDown: true, at: 3.01), "A stale positive physical read cannot resurrect a released drag")
pointer.event(down: true, at: 4)
_ = pointer.reconcile(physicalDown: false, at: 4.01)
check(!pointer.reconcile(physicalDown: false, at: 4.2), "Recover from a missing mouse-up event")
check(pointer.reconcile(physicalDown: true, at: 5), "Recover drag already in progress")
var modifiers = WheelModifierState()
for code: UInt16 in [123, 124, 125, 126, 122, 120, 90] {
  modifiers.changed(flags: .function, keyCode: code)
  check(!modifiers.normalized(.function, physicalFn: false).contains(.function), "Navigation keys cannot impersonate Fn")
}
modifiers.changed(flags: .function, keyCode: 63)
check(modifiers.normalized([], physicalFn: false).contains(.function), "Physical Fn is latched until release")
modifiers.changed(flags: [], keyCode: 63)
check(!modifiers.normalized(.function, physicalFn: false).contains(.function), "Fn release is observed")
check(modifiers.normalized([], physicalFn: true).contains(.function), "Fn held before drag is supported")
modifiers.changed(flags: .function, keyCode: 63)
modifiers.reconcile(flags: [], physicalFn: false, at: 1)
modifiers.reconcile(flags: [], physicalFn: false, at: 1.2)
check(!modifiers.normalized([], physicalFn: false).contains(.function), "Missing Fn-up cannot leave the key stuck")
modifiers.mouseChanged(flags: .function)
check(modifiers.normalized(.function, physicalFn: false).contains(.function), "Mouse events support Fn held before dragging")
modifiers.mouseChanged(flags: [])
check(!modifiers.normalized([], physicalFn: false).contains(.function), "Mouse events also release Fn")

check(WheelGeometry.backdropPath(center:.zero).contains(.zero),"Glass backdrop covers the centre")
check(WheelGeometry.backdropPath(center:.zero).contains(CGPoint(x:80,y:0)),"Glass backdrop covers petal gutters")
for anchor in [CGPoint.zero, CGPoint(x:0.5,y:0.5)] {
  for pointer in [CGPoint(x:136,y:136), CGPoint(x:28,y:210)] {
    let transform = WheelGeometry.openingTransform(scale:0.78,pointer:pointer,
      bounds:CGRect(x:0,y:0,width:272,height:272),anchor:anchor)
    let pivot = CGPoint(x:272*anchor.x,y:272*anchor.y)
    let fixed = CGPoint(x:pivot.x+(pointer.x-pivot.x)*transform.m11+transform.m41,
                        y:pivot.y+(pointer.y-pivot.y)*transform.m22+transform.m42)
    check(abs(fixed.x-pointer.x)<0.0001 && abs(fixed.y-pointer.y)<0.0001,
      "Opening animation stays centred on the pointer")
  }
}
print("PASS \(assertions) drag assertions; 1,048,576 modifier sequences; release, cancellation, delayed callbacks and exactly-once commits")
