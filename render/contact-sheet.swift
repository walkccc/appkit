#!/usr/bin/env swift

// contact-sheet — every store card in one picture.
//
//   printf 'ja\t01-board\tstore/screenshots/ja/01-board.png\tchanged\n' \
//     | contact-sheet --out .build/review/screenshots.png --title Tefuda
//
// Reads `locale<TAB>label<TAB>path<TAB>status` on stdin and draws one row per
// locale, one column per card. `git status` answers WHETHER a card changed;
// this answers WHICH, in every language at once — which is the question a
// binary diff in a terminal cannot be asked.
//
// Status is `new`, `changed` or `same`, and only the first two get a frame: a
// sheet where everything is marked is a sheet nobody reads.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// ============================================================================
// Arguments
// ============================================================================

var out = ""
var title = ""
var thumbWidth = 200.0
var scale = 2.0
var arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("error: \(message)\n".utf8))
  exit(2)
}

while let flag = arguments.first {
  arguments.removeFirst()
  guard let value = arguments.first else { fail("\(flag) needs a value") }
  arguments.removeFirst()
  switch flag {
  case "--out": out = value
  case "--title": title = value
  case "--width":
    guard let width = Double(value), width >= 40 else { fail("--width needs a number ≥ 40") }
    thumbWidth = width
  case "--scale":
    guard let factor = Double(value), factor >= 1, factor <= 4
    else { fail("--scale needs a number between 1 and 4") }
    scale = factor
  default: fail("unknown argument: \(flag)")
  }
}

if out.isEmpty {
  fail("--out is required")
}

// ============================================================================
// The sheet
// ============================================================================

struct Cell {
  let path: String
  let status: String
}

/// First-seen order throughout, never sorted here: the caller walks the locales
/// and the numbered card files in the order the store shows them, and a sheet
/// that reordered them would stop matching the listing it is reviewing.
var locales: [String] = []
var labels: [String] = []
var cells: [String: [String: Cell]] = [:]

while let line = readLine(strippingNewline: true) {
  let field = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
  guard field.count == 4 else { continue }
  let (locale, label, path, status) = (field[0], field[1], field[2], field[3])
  if !locales.contains(locale) {
    locales.append(locale)
  }
  if !labels.contains(label) {
    labels.append(label)
  }
  cells[locale, default: [:]][label] = Cell(path: path, status: status)
}

if locales.isEmpty {
  fail("nothing on stdin — no cards to draw")
}

func load(_ path: String) -> CGImage? {
  guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
  else { return nil }
  return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// Decoded once, up front: a card appears in exactly one cell, and the sheet
/// needs every one of their aspect ratios before it can size a row.
var loaded: [String: CGImage] = [:]
for locale in locales {
  for (_, cell) in cells[locale] ?? [:] {
    loaded[cell.path] = load(cell.path)
  }
}

/// The cell box is sized from the TALLEST card on the sheet, and everything
/// else is letterboxed inside it. A watch card is a third the height of a
/// phone card, and scaling each row to its own aspect would draw a grid whose
/// rows do not line up — the one thing a contact sheet exists to do.
let tallest = loaded.values.map { Double($0.height) / Double($0.width) }
  .max() ?? (2_688.0 / 1_242.0)
let thumbHeight = (thumbWidth * tallest).rounded()

/// Chrome is deliberately thin. Every point spent on padding is a point not
/// spent on a card, and the cards are the whole picture — a sheet is read by
/// scanning six thumbnails across for the one that moved, not by admiring its
/// margins.
let pad = 20.0
let gutter = 9.0
let localeColumn = 68.0
let localeGap = 14.0
let headerRow = 20.0
let titleBar = title.isEmpty ? 0.0 : 46.0

let width = pad + localeColumn + Double(labels.count) * (thumbWidth + gutter) - gutter + pad
let contentTop = pad + titleBar + headerRow
let height = contentTop + Double(locales.count) * (thumbHeight + gutter) - gutter + pad

/// Laid out in points and rasterised at `scale`, so the sheet is sharp on the
/// display it is read on. It matters more here than anywhere else in the kit:
/// a cell is a 1242pt-wide card shrunk to 200, and at 1× the caption a reviewer
/// is checking lands on too few pixels to read at all.
let pixelWidth = Int((width * scale).rounded())
let pixelHeight = Int((height * scale).rounded())

guard let context = CGContext(
  data: nil,
  width: pixelWidth, height: pixelHeight,
  bitsPerComponent: 8, bytesPerRow: 0,
  space: CGColorSpaceCreateDeviceRGB(),
  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fail("could not make a \(pixelWidth)x\(pixelHeight) canvas") }

context.scaleBy(x: scale, y: scale)
// The default is .low, which is a box filter: shrinking a card by 6× through it
// is what made every earlier sheet look like a photograph of a screen.
context.interpolationQuality = .high

let canvasHeight = Double(pixelHeight) / scale

/// CoreGraphics puts the origin at the bottom left and this sheet is laid out
/// from the top, so every rectangle is built through here rather than each
/// call site remembering to flip.
func box(x: Double, top: Double, width: Double, height: Double) -> CGRect {
  CGRect(x: x, y: canvasHeight - top - height, width: width, height: height)
}

func grey(_ value: Double, _ alpha: Double = 1) -> CGColor {
  CGColor(red: value, green: value, blue: value, alpha: alpha)
}

// The blog and the sites this ships beside are #FAFAF8 on #0B0C0E; the sheet
// borrows the paper so a screenshot of it sits in the same family.
let paper = CGColor(red: 0.980, green: 0.980, blue: 0.973, alpha: 1)
let ink = CGColor(red: 0.043, green: 0.047, blue: 0.055, alpha: 1)
let red = CGColor(red: 0.898, green: 0.282, blue: 0.302, alpha: 1)
let green = CGColor(red: 0.188, green: 0.639, blue: 0.424, alpha: 1)

context.setFillColor(paper)
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

enum Align { case left, center, right }

func write(
  _ text: String, x: Double, top: Double, size: Double,
  weight: NSFont.Weight = .regular, color: CGColor = ink, align: Align = .left, limit: Double = 0,
  tracking: Double = 0
) {
  guard !text.isEmpty else { return }
  let font = NSFont.systemFont(ofSize: size, weight: weight)
  let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(cgColor: color) ?? .black,
    .kern: tracking,
  ]
  var string = text
  var line = CTLineCreateWithAttributedString(NSAttributedString(
    string: string, attributes: attributes
  ))
  // Truncated by dropping characters rather than by CoreText, so the ellipsis
  // is the one this file draws and a label never silently runs into its
  // neighbour.
  if limit > 0 {
    while CTLineGetTypographicBounds(line, nil, nil, nil) > limit, string.count > 1 {
      string = String(string.dropLast())
      line = CTLineCreateWithAttributedString(NSAttributedString(
        string: string + "…", attributes: attributes
      ))
    }
  }
  let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
  let origin: Double = switch align {
  case .left: x
  case .center: x - advance / 2
  case .right: x - advance
  }
  context.textPosition = CGPoint(x: origin, y: canvasHeight - top - size)
  CTLineDraw(line, context)
}

var changed = 0
var missing = 0
for locale in locales {
  for (_, cell) in cells[locale] ?? [:] {
    if cell.status == "changed" || cell.status == "new" {
      changed += 1
    }
    if loaded[cell.path] == nil {
      missing += 1
    }
  }
}

let total = locales.reduce(0) { $0 + (cells[$1]?.count ?? 0) }

if !title.isEmpty {
  write(title, x: pad, top: pad - 1, size: 19, weight: .semibold)
  var summary = "\(total) cards · \(locales.count) locales · "
    + (changed == 0 ? "nothing changed" : "\(changed) new or changed")
  if missing > 0 {
    summary += " · \(missing) unreadable"
  }
  write(summary, x: pad, top: pad + 24, size: 11, color: grey(0.45))

  // A hairline instead of empty space: the header and the grid are different
  // kinds of thing, and at this padding whitespace alone stopped saying so.
  context.setFillColor(grey(0.90))
  context.fill(box(x: pad, top: pad + titleBar - 10, width: width - pad * 2, height: 1))
}

for (column, label) in labels.enumerated() {
  let x = pad + localeColumn + Double(column) * (thumbWidth + gutter)
  write(
    label, x: x + thumbWidth / 2, top: pad + titleBar + 3, size: 10,
    weight: .medium, color: grey(0.45), align: .center, limit: thumbWidth, tracking: 0.3
  )
}

for (row, locale) in locales.enumerated() {
  let top = contentTop + Double(row) * (thumbHeight + gutter)
  write(
    locale, x: pad + localeColumn - localeGap, top: top + thumbHeight / 2 - 6, size: 12,
    weight: .medium, align: .right, limit: localeColumn - localeGap
  )

  for (column, label) in labels.enumerated() {
    let x = pad + localeColumn + Double(column) * (thumbWidth + gutter)
    let frame = box(x: x, top: top, width: thumbWidth, height: thumbHeight)

    guard let cell = cells[locale]?[label] else {
      // A card this locale does not have. Drawn as an empty well rather than
      // skipped, because a hole in the grid IS the finding: one locale short of
      // a scene is exactly what this sheet is for.
      context.setFillColor(grey(0.94))
      context.fill(frame)
      write(
        "—", x: x + thumbWidth / 2, top: top + thumbHeight / 2 - 8, size: 14,
        color: grey(0.72), align: .center
      )
      continue
    }

    if let image = loaded[cell.path] {
      // Letterboxed inside the cell, centred, never cropped — a card whose
      // edges are cut off is a card whose caption might be too.
      let scale = min(thumbWidth / Double(image.width), thumbHeight / Double(image.height))
      let drawn = CGSize(
        width: (Double(image.width) * scale).rounded(),
        height: (Double(image.height) * scale).rounded()
      )
      context.draw(image, in: box(
        x: x + (thumbWidth - drawn.width) / 2,
        top: top + (thumbHeight - drawn.height) / 2,
        width: drawn.width, height: drawn.height
      ))
    } else {
      context.setFillColor(grey(0.94))
      context.fill(frame)
      write(
        "unreadable", x: x + thumbWidth / 2, top: top + thumbHeight / 2 - 6, size: 10,
        color: red, align: .center, limit: thumbWidth
      )
    }

    switch cell.status {
    case "new", "changed":
      context.setStrokeColor(cell.status == "new" ? green : red)
      context.setLineWidth(2.5)
      context.stroke(frame.insetBy(dx: 1.25, dy: 1.25))
    default:
      // Thinner than a point: this hairline only has to say "a card ends here",
      // and at the weight it used to be, thirty of them read as the grid rather
      // than the cards did.
      context.setStrokeColor(grey(0.88))
      context.setLineWidth(0.75)
      context.stroke(frame.insetBy(dx: 0.375, dy: 0.375))
    }
  }
}

guard let image = context.makeImage() else { fail("could not draw the sheet") }
let url = URL(fileURLWithPath: out)
try? FileManager.default.createDirectory(
  at: url.deletingLastPathComponent(), withIntermediateDirectories: true
)
guard let destination = CGImageDestinationCreateWithURL(
  url as CFURL, UTType.png.identifier as CFString, 1, nil
) else { fail("could not write \(out)") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("could not write \(out)") }

print("\(pixelWidth)x\(pixelHeight)")
