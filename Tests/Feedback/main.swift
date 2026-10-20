import Foundation

for count in [1, 2, 5, 100] {
  var gate = WheelFeedbackGate()
  var impulses = 0
  for index in 0..<count {
    let time = Double(index) * 0.02
    if gate.selectionChanged(to: "convert:pdf", at: time) { impulses += 1 }
    _ = gate.selectionChanged(to: nil, at: time + 0.005)
  }
  precondition(impulses == 1, "Batch of \(count): one impulse for the same button")
  precondition(gate.selectionChanged(to: "archive", at: Double(count) * 0.02), "Different button gets its own impulse")
}
var gate = WheelFeedbackGate()
precondition(gate.selectionChanged(to: "compress", at: 0))
precondition(!gate.selectionChanged(to: nil, at: 1))
precondition(!gate.selectionChanged(to: "compress", at: 1.01), "Brief exit is not a new hover")
precondition(!gate.selectionChanged(to: nil, at: 2))
precondition(gate.selectionChanged(to: "compress", at: 2.2), "Deliberate re-entry gets feedback")
print("PASS: one impulse for batches of 1/2/5/100, different buttons preserved, brief exits filtered, deliberate re-entry preserved")
