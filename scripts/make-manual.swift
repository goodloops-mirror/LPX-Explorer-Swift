// Renders docs/manual.html to docs/LPX Explorer Manual.pdf (A4, paginated). Run from the repo root:
//   swift scripts/make-manual.swift
// Build-time tool only: it uses AppKit's HTML importer, which the app itself never does.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("docs/manual.html")
let output = root.appendingPathComponent("docs/LPX Explorer Manual.pdf")

_ = NSApplication.shared
guard let html = try? Data(contentsOf: source),
      let text = try? NSAttributedString(data: html, options: [.documentType: NSAttributedString.DocumentType.html,
                                                          .characterEncoding: String.Encoding.utf8.rawValue,
                                                          .baseURL: root], documentAttributes: nil) else {
    FileHandle.standardError.write(Data("cannot read docs/manual.html\n".utf8)); exit(1)
}

let page = NSSize(width: 595, height: 842)      // A4 in points
let margin: CGFloat = 54
let info = NSPrintInfo()
info.paperSize = page
info.topMargin = margin; info.bottomMargin = margin; info.leftMargin = margin; info.rightMargin = margin
info.horizontalPagination = .fit
info.isVerticallyCentered = false
info.jobDisposition = .save
info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output

let width = page.width - 2 * margin
let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: page.height))
view.isVerticallyResizable = true
view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
view.textContainer?.widthTracksTextView = true
view.textStorage?.setAttributedString(text)
view.layoutManager?.ensureLayout(for: view.textContainer!)
view.sizeToFit()

let operation = NSPrintOperation(view: view, printInfo: info)
operation.showsPrintPanel = false
operation.showsProgressPanel = false
guard operation.run() else { FileHandle.standardError.write(Data("printing failed\n".utf8)); exit(1) }
print("wrote \(output.path)")
