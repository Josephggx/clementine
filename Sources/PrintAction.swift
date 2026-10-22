import AppKit
import PDFKit

/// Scope window changes to this print panel's modal session. NSPrintPanel does
/// not expose its window, so observe the modal window only while it is running.
private final class ClementinePrintPanel: NSPrintPanel {
  override func runModal(with printInfo: NSPrintInfo) -> Int {
    let previousModal = NSApp.modalWindow
    let controls = PrintPanelWindowControls()
    let timer = Timer(timeInterval:0.03,repeats:true) { _ in
      guard let window = NSApp.modalWindow, window !== previousModal else { return }
      controls.attach(to:window)
    }
    RunLoop.main.add(timer,forMode:.modalPanel)
    RunLoop.main.add(timer,forMode:.common)
    defer {timer.invalidate(); controls.detach()}
    return super.runModal(with:printInfo)
  }
}

private final class PrintPanelWindowControls: NSObject {
  private weak var window: NSWindow?
  private var originalStyle: NSWindow.StyleMask?
  private weak var closeTarget: AnyObject?
  private var closeAction: Selector?
  private var zoomHidden = false
  private var zoomEnabled = true

  func attach(to candidate: NSWindow) {
    guard window == nil else { return }
    window = candidate
    originalStyle = candidate.styleMask
    closeTarget = candidate.standardWindowButton(.closeButton)?.target
    closeAction = candidate.standardWindowButton(.closeButton)?.action
    zoomHidden = candidate.standardWindowButton(.zoomButton)?.isHidden ?? false
    zoomEnabled = candidate.standardWindowButton(.zoomButton)?.isEnabled ?? true
    candidate.styleMask.insert([.titled,.closable])
    candidate.styleMask.remove(.resizable)
    candidate.standardWindowButton(.closeButton)?.target = self
    candidate.standardWindowButton(.closeButton)?.action = #selector(cancelPrinting)
    candidate.standardWindowButton(.closeButton)?.isEnabled = true
    candidate.standardWindowButton(.closeButton)?.isHidden = false
    candidate.standardWindowButton(.zoomButton)?.isEnabled = false
    candidate.standardWindowButton(.zoomButton)?.isHidden = true
  }

  @objc private func cancelPrinting() {
    NSApp.stopModal(withCode:.cancel)
    window?.orderOut(nil)
  }

  func detach() {
    guard let window else {return}
    if let originalStyle {window.styleMask = originalStyle}
    window.standardWindowButton(.closeButton)?.target = closeTarget
    window.standardWindowButton(.closeButton)?.action = closeAction
    window.standardWindowButton(.zoomButton)?.isHidden = zoomHidden
    window.standardWindowButton(.zoomButton)?.isEnabled = zoomEnabled
    self.window = nil
  }
}

enum PrintEligibility {
  static func supports(_ files:[URL])->Bool {
    !files.isEmpty && files.allSatisfy {
      !Family.isFolder($0) && $0.pathExtension.lowercased() != "epub" &&
        [.pdf,.document,.sheet,.image,.presentation].contains(Family.of($0))
    }
  }
}

/// Prepare one print job, then let macOS ask for printer, pages and confirmation.
/// Only temporary copies are generated; the source files are never rewritten.
final class PrintAction {
  static let shared=PrintAction()
  private(set) var busy=false
  private init() {}

  static func prepare(_ files:[URL],in root:URL,options:Options)throws->PDFDocument {
    guard PrintEligibility.supports(files) else {throw ClementineError(tr("Aucun fichier imprimable."))}
    let engine=Engine(),combined=PDFDocument()
    for (index,file) in files.enumerated() {
      guard FileManager.default.fileExists(atPath:file.path) else {
        throw ClementineError(tr("Document illisible pour l’impression : \(file.lastPathComponent)"))
      }
      let inputs:[URL]
      if Family.of(file) == .pdf {inputs=[file]}
      else {
        let stage=root.appendingPathComponent("item-\(index)",isDirectory:true)
        try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:true)
        inputs=try engine.convert(file,to:"pdf",stage:stage,o:options)
      }
      for input in inputs {
        guard let document=PDFDocument(url:input),!document.isLocked,document.pageCount>0 else {
          throw ClementineError(tr("Document illisible pour l’impression : \(file.lastPathComponent)"))
        }
        guard document.allowsPrinting else {
          throw ClementineError(tr("Ce PDF ne permet pas l’impression : \(file.lastPathComponent)"))
        }
        for number in 0..<document.pageCount {
          guard let page=document.page(at:number)?.copy() as? PDFPage else {
            throw ClementineError(tr("Impossible de préparer l’impression."))
          }
          combined.insert(page,at:combined.pageCount)
        }
      }
    }
    guard combined.pageCount>0 else {throw ClementineError(tr("Impossible de préparer l’impression."))}
    return combined
  }

  func start(_ files:[URL],options:Options,onError:@escaping(Error)->Void) {
    guard !busy,PrintEligibility.supports(files) else {return}
    busy=true
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("clementine-print-"+UUID().uuidString,isDirectory:true)
    DispatchQueue.global(qos:.userInitiated).async {
      let result=Result {try Self.prepare(files,in:root,options:options)}
      DispatchQueue.main.async {
        defer {self.busy=false;try? FileManager.default.removeItem(at:root)}
        do {
          let document=try result.get()
          guard let operation=document.printOperation(for:NSPrintInfo.shared.copy() as? NSPrintInfo,
            scalingMode:.pageScaleToFit,autoRotate:true) else {
            throw ClementineError(tr("Impossible de préparer l’impression."))
          }
          operation.jobTitle=files.count == 1 ? files[0].lastPathComponent : "Clémentine — \(files.count) \(tr("fichiers"))"
          operation.printPanel = ClementinePrintPanel()
          operation.showsPrintPanel=true;operation.showsProgressPanel=true
          // run() presents the system print panel. Cancel does not print or error.
          withExtendedLifetime(document) {_ = operation.run()}
        } catch {onError(error)}
      }
    }
  }
}
