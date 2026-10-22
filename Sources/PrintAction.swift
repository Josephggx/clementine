import AppKit
import PDFKit

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
          operation.showsPrintPanel=true;operation.showsProgressPanel=true
          // run() presents the system print panel. Cancel does not print or error.
          withExtendedLifetime(document) {_ = operation.run()}
        } catch {onError(error)}
      }
    }
  }
}
