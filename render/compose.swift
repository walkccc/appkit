#!/usr/bin/env swift

// compose — store cards from raw captures, drawn with CoreGraphics and
// CoreText, from a storyboard the app repo owns.
//
//   compose --cards store/cards.json --captures .screenshots \
//           --out store/screenshots --fonts <appkit>/render/fonts \
//           --appkit <appkit>
//
// Same storyboard and captures in, same bytes out — which is what makes
// `git status -- store/screenshots` a real answer to "did any screen change".
// CoreText because it is the only thing on the machine that lays out Japanese
// and Korean beside Latin from an explicit cascade rather than a guess.
//
// The storyboard is JSON so that it is data: another renderer, or a preview,
// reads the same file. Schema: docs/CARDS.md.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// ============================================================================
// The storyboard
// ============================================================================

/// A localizable string: one entry per capture language, plus an optional
/// `default`. A locale with no entry falls back to `default`, then to `en` —
/// never to nothing, because a card silently missing its headline still renders
/// and still uploads.
struct Text: Decodable {
  let values: [String: String]

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let one = try? container.decode(String.self) {
      values = ["default": one]
    } else {
      values = try container.decode([String: String].self)
    }
  }

  func callAsFunction(_ locale: String) -> String {
    values[locale] ?? values["default"] ?? values["en"] ?? ""
  }
}

struct Size: Decodable {
  let width: Int
  let height: Int
}

struct Background: Decodable {
  let type: String?
  let color: String?
  let colors: [String]?
  let angle: Double?
  let image: String?
}

/// A typeface the storyboard can name. `files` maps a weight to a font file
/// resolved against appkit's fonts directory and then the repo; `family` names
/// one already installed. A face that resolves to neither falls back to the
/// system font and says so — a card is allowed to render, but not quietly in
/// the wrong typeface.
struct Face: Decodable {
  let family: String?
  let files: [String: String]?
  /// Per-language faces appended to the cascade, so Latin comes from the named
  /// file and CJK from the platform's own. Keyed by capture language.
  let cjk: [String: String]?
}

struct Line: Decodable {
  let text: Text
  let font: String?
  let size: Double
  let weight: Double?
  let color: String
  let align: String?
  let lineHeight: Double?
  let tracking: Double?
}

struct Caption: Decodable {
  /// Where the block's centre sits, as a percentage of card height.
  let at: Double
  let lines: [Line]
  let inset: Double?
}

/// A device on a card. `at`/`x` place its CENTRE as a percentage of the travel:
/// 0 puts the device's far edge against the travel's near edge, 100 the other
/// way round, 50 centres it. The device is free to overflow either edge, which
/// is the whole point — a card usually shows the top two thirds of a phone.
struct DeviceLayout: Decodable {
  let model: String?
  let scene: String?
  let image: String?
  let at: Double
  let x: Double?
  let zoom: Double
  let rotate: Double?
  let layer: Int?
}

/// One item on a card, in a box given as percentages of the card. Three kinds,
/// told apart by which field is set:
///
///   `scene`/`image`/`localized`   a picture
///   `shape`                       a drawn box — `fill`, `stroke`, `radius`
///   `text`                        a localized paragraph, wrapped into the box
///
/// They share one list because the list order IS the z-order, and a drawn tile
/// has to be painted before the type that sits in it. Splitting them into
/// `shapes` and `texts` would put that ordering somewhere nothing can see it.
struct Element: Decodable {
  /// Either a `scene` — a capture, resolved per language the way a device's is
  /// — or an `image`, a path in the repo. A widget render and a phone capture
  /// are both things the app was photographed doing, so both come out of the
  /// same per-language folder and neither needs a path per locale written down.
  let scene: String?
  let image: String?
  let localized: [String: String]?
  /// `rect` (rounded by `radius`) or `ellipse`.
  let shape: String?
  let text: Text?

  let x: Double
  let y: Double
  let width: Double
  let height: Double
  /// A percentage of the CARD's width, not the element's, so a tile and the
  /// picture dropped into it round by the same amount.
  let radius: Double?
  let rotate: Double?
  let fit: String?

  // A shape.
  let fill: String?
  let stroke: String?
  /// Also a percentage of the card's width. 0.15 is about a hairline at 1242.
  let strokeWidth: Double?

  // A paragraph. The same vocabulary a caption's line takes, because it is the
  // same thing in a box of its own rather than in the block.
  let font: String?
  let size: Double?
  let weight: Double?
  let color: String?
  let align: String?
  /// `top` (the default), `middle` or `bottom`. Worth having because the whole
  /// point of a text box is that ten languages of different lengths land in the
  /// same shape, and they only look placed rather than dropped in if the block
  /// is centred in it — German wraps to two lines where Japanese takes one.
  let valign: String?
  let lineHeight: Double?
  let tracking: Double?
}

/// Where the screen sits inside a bezel image, as percentages of the frame, so
/// it survives any scale. `radiusX`/`radiusY` resolve against width and height
/// separately — 6/6 on an iPhone is an ellipse, deliberately, because that is
/// the squircle.
struct ScreenWindow: Decodable {
  let left: Double
  let top: Double
  let width: Double
  let height: Double
  let radiusX: Double
  let radiusY: Double
}

struct Device: Decodable {
  /// Either a photographed `frame` — a bezel PNG with `screen` naming the
  /// window inside it — or a drawn one: `aspect`, `radius` and `bezel`, the
  /// last two as a fraction of the device's own width.
  let frame: String?
  let screen: ScreenWindow?

  let aspect: Double?
  let radius: Double?
  let bezel: Double?
  let color: String?
  let shadow: Double?
  /// The polished edge on a drawn device, as a hairline just inside the body.
  /// Without it a drawn phone reads as a black rectangle rather than a device.
  let rim: String?
}

struct Card: Decodable {
  let name: String
  let background: Background?
  let device: DeviceLayout?
  let extraDevices: [DeviceLayout]?
  let elements: [Element]?
  let caption: Caption?
  /// Two adjacent cards sharing a `span` name carry one device across both. The
  /// first is the lead and holds the layout; the second shows the continuation.
  let span: String?
  /// Locales this card is skipped for — a screen that only exists in some
  /// languages, rather than a set that quietly differs in length.
  let skip: [String]?
  /// A card that is not a screenshot: Play's feature graphic is 1024×500 and
  /// its store icon is 512×512, and both are mandatory. They are cards because
  /// they are the same object as every other one here — a background, a mark
  /// and a line of type on a canvas — and only the canvas is a different shape.
  let size: Size?
  /// A subfolder under the locale, and its own numbering. The uploader reads
  /// `<locale>/*.png` as the screenshots and `<locale>/<kind>/` as the other
  /// imagery, so this is what keeps a feature graphic out of the gallery.
  let dir: String?
}

struct Storyboard: Decodable {
  let card: Size
  let fonts: [String: Face]?
  let devices: [String: Device]?
  let defaultDevice: String?
  let locales: [Locale]
  let cards: [Card]

  struct Locale: Decodable {
    /// The capture folder, which is also the language the copy is written in.
    let capture: String
    /// The folder the cards land in — a store's own spelling of the same
    /// language. Two locales may share one capture (`es-ES` and `es-MX`).
    let out: String
  }
}

// ============================================================================
// Arguments
// ============================================================================

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("error: \(message)\n".utf8))
  exit(1)
}

var cardsPath = ""
var capturesDir = ""
var outDir = ""
var fontsDir = ""
var appkitDir = ""
var onlyLocales: [String] = []
var onlyCards: [String] = []

var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
  let flag = arguments.removeFirst()
  func value() -> String {
    guard !arguments.isEmpty else { fail("\(flag) needs a value") }
    return arguments.removeFirst()
  }
  switch flag {
  case "--cards": cardsPath = value()
  case "--captures": capturesDir = value()
  case "--out": outDir = value()
  case "--fonts": fontsDir = value()
  case "--appkit": appkitDir = value()
  case "--locale": onlyLocales.append(value())
  case "--card": onlyCards.append(value())
  default: fail("unknown argument: \(flag)")
  }
}
guard !cardsPath.isEmpty, !capturesDir.isEmpty, !outDir.isEmpty else {
  fail(
    "usage: compose --cards <file> --captures <dir> --out <dir> "
      + "[--fonts <dir>] [--appkit <dir>] [--locale <code>] [--card <name|number|range>]"
  )
}

let storyboardURL = URL(fileURLWithPath: cardsPath)
let repoRoot = storyboardURL.deletingLastPathComponent().deletingLastPathComponent()
let appkitRoot = appkitDir.isEmpty ? nil : URL(fileURLWithPath: appkitDir)
guard let storyboardData = try? Data(contentsOf: storyboardURL) else {
  fail("cannot read \(cardsPath)")
}
let storyboard: Storyboard
do {
  storyboard = try JSONDecoder().decode(Storyboard.self, from: storyboardData)
} catch {
  fail("\(cardsPath): \(error)")
}

/// One `--card`: a name, a number, or a `6..8` range of numbers. Numbers because
/// they are what is in the filenames, and the filenames are what the person
/// iterating on one layout is looking at.
enum CardSelector {
  case name(String)
  case numbers(ClosedRange<Int>)

  init(_ text: String) {
    if let dots = text.range(of: "..") {
      guard let low = Int(text[..<dots.lowerBound]),
        let high = Int(text[dots.upperBound...]), low <= high
      else { fail("--card \(text): a range is two card numbers, lower first") }
      self = .numbers(low...high)
    } else if let one = Int(text) {
      self = .numbers(one...one)
    } else {
      self = .name(text)
    }
  }

  func matches(_ card: Card, number: Int) -> Bool {
    switch self {
    case .name(let name): return card.name == name
    case .numbers(let range): return range.contains(number)
    }
  }

  var text: String {
    switch self {
    case .name(let name): return name
    case .numbers(let range):
      return range.lowerBound == range.upperBound
        ? String(range.lowerBound) : "\(range.lowerBound)..\(range.upperBound)"
    }
  }
}

let selectors = onlyCards.map(CardSelector.init)

/// Cards are filtered at the WRITE and never out of the list. Numbering is a
/// running counter and a spanning card reads its device layout back out of
/// `cards` by position, so a trimmed list would renumber the whole set and draw
/// half a hero onto a card that is not the lead.
func wanted(_ card: Card, number: Int) -> Bool {
  selectors.isEmpty || selectors.contains { $0.matches(card, number: number) }
}

// Every selector must match something. One that matches nothing is the failure
// `--device-type` already has upstream — it narrows to zero and reports success
// — so a mistyped name stops here rather than rendering an empty pass.
if !selectors.isEmpty {
  var counters: [String: Int] = [:]
  var hit = Set<Int>()
  // Against a numbering that skips nothing: `skip` is per locale, and a
  // selector valid in one language and a typo in another is worse than either.
  for card in storyboard.cards {
    let folder = card.dir ?? ""
    counters[folder, default: 0] += 1
    for (index, selector) in selectors.enumerated()
    where selector.matches(card, number: counters[folder]!) {
      hit.insert(index)
    }
  }
  let missed = selectors.indices.filter { !hit.contains($0) }.map { selectors[$0].text }
  guard missed.isEmpty else {
    fail("--card \(missed.joined(separator: ", ")): no such card in \(cardsPath)")
  }
}

// ============================================================================
// Colour, images, geometry
// ============================================================================

/// `#RRGGBB` or `#RRGGBBAA`. Written in the storyboard the way the app's own
/// design tokens are written, so the two can be diffed by eye.
func color(_ hex: String) -> CGColor {
  var text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
  if text.count == 6 { text += "FF" }
  guard text.count == 8, let value = UInt32(text, radix: 16) else {
    fail("not a colour: \(hex)")
  }
  return CGColor(
    srgbRed: CGFloat((value >> 24) & 0xFF) / 255,
    green: CGFloat((value >> 16) & 0xFF) / 255,
    blue: CGFloat((value >> 8) & 0xFF) / 255,
    alpha: CGFloat(value & 0xFF) / 255
  )
}

/// Decoded once and kept: a hero capture is drawn onto a card per locale, and
/// several cards share one glyph.
final class ImageCache {
  private var cache: [String: CGImage] = [:]
  private let lock = NSLock()

  func image(_ path: String) -> CGImage? {
    lock.lock()
    defer { lock.unlock() }
    if let hit = cache[path] { return hit }
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    cache[path] = image
    return image
  }
}

let images = ImageCache()

/// A path relative to the repo root, so a storyboard names art the way the repo
/// does — `store/art/icon.png`, not `../../store/art/icon.png`.
func resolve(_ path: String) -> String {
  path.hasPrefix("/") ? path : repoRoot.appendingPathComponent(path).path
}

/// A `frame` names a bezel PNG. A bare filename — no `/` — is one of appkit's
/// own, in `render/bezels/`: the phone and the watch are each one photograph,
/// pinned in appkit the way the capture device itself is, so no repo keeps a
/// copy or writes a path to reach it. A name with a `/` is the repo's own art,
/// for a bezel no other app on appkit ships.
func resolveFrame(_ path: String) -> String {
  guard !path.contains("/") else { return resolve(path) }
  guard let appkitRoot else { fail("\(path) needs --appkit") }
  return appkitRoot.appendingPathComponent("render/bezels").appendingPathComponent(path).path
}

/// The rect an image fills inside a frame, cropped or letterboxed.
func fitted(_ image: CGImage, in frame: CGRect, fit: String) -> CGRect {
  let source = CGSize(width: image.width, height: image.height)
  let scale = fit == "contain"
    ? min(frame.width / source.width, frame.height / source.height)
    : max(frame.width / source.width, frame.height / source.height)
  let size = CGSize(width: source.width * scale, height: source.height * scale)
  return CGRect(
    x: frame.midX - size.width / 2,
    y: frame.midY - size.height / 2,
    width: size.width,
    height: size.height
  )
}

/// Where a device's centre lands, given the percentage placement above.
func centre(percent: Double, span: Double, travel: Double) -> Double {
  -span / 2 + (percent / 100) * (travel + span)
}

// ============================================================================
// Type
// ============================================================================

/// Fonts registered once, before any card is drawn. Registration is process-
/// wide and not thread-safe, which is why it happens here and not lazily inside
/// a render.
final class Typefaces {
  private var registered: [String: String] = [:]  // file path -> PostScript name
  private var warned = Set<String>()

  init(faces: [String: Face], fontsDir: String) {
    for face in faces.values {
      for file in (face.files ?? [:]).values {
        for base in [fontsDir, repoRoot.path] where !base.isEmpty {
          let url = URL(fileURLWithPath: base).appendingPathComponent(file)
          guard FileManager.default.fileExists(atPath: url.path) else { continue }
          var error: Unmanaged<CFError>?
          CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
          if let name = Self.postScriptName(of: url) {
            registered[file] = name
          }
          break
        }
      }
    }
  }

  private static func postScriptName(of url: URL) -> String? {
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
      as? [CTFontDescriptor], let first = descriptors.first
    else { return nil }
    return CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
  }

  /// The face a line is drawn in, with the language's own CJK face appended as
  /// a cascade. Explicit rather than left to CoreText: the implicit fallback for
  /// Han characters depends on the system's language order, so the same card
  /// rendered on two machines came out in two typefaces.
  func font(_ face: Face?, size: Double, weight: Double, language: String) -> CTFont {
    var base: CTFont
    if let file = face?.files?[String(Int(weight))] ?? face?.files?["400"],
       let name = registered[file] {
      base = CTFontCreateWithName(name as CFString, size, nil)
    } else if let family = face?.family,
              let found = NSFont(name: family, size: size) {
      base = found
    } else {
      if let family = face?.family, !warned.contains(family) {
        warned.insert(family)
        FileHandle.standardError.write(
          Data("compose: no font '\(family)' — using the system face\n".utf8))
      }
      base = NSFont.systemFont(ofSize: size, weight: nsWeight(weight))
    }
    guard let cjk = face?.cjk?[language] ?? face?.cjk?["default"] else { return base }
    let fallback = CTFontDescriptorCreateWithAttributes(
      [kCTFontNameAttribute: cjk] as CFDictionary)
    let descriptor = CTFontDescriptorCreateCopyWithAttributes(
      CTFontCopyFontDescriptor(base),
      [kCTFontCascadeListAttribute: [fallback]] as CFDictionary
    )
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
  }

  private func nsWeight(_ weight: Double) -> NSFont.Weight {
    switch weight {
    case ..<350: return .light
    case ..<450: return .regular
    case ..<550: return .medium
    case ..<650: return .semibold
    case ..<750: return .bold
    default: return .heavy
    }
  }
}

let typefaces = Typefaces(faces: storyboard.fonts ?? [:], fontsDir: fontsDir)

// ============================================================================
// Drawing
// ============================================================================

let defaultCardSize = CGSize(width: storyboard.card.width, height: storyboard.card.height)

func newContext(_ size: CGSize, opaque: Bool = true) -> CGContext {
  // A card is opaque: App Store Connect and the Play Console both refuse an
  // alpha channel, and one that has it fails at upload rather than at render.
  // The intermediate a spanning device is drawn on is not — it has to composite
  // onto the background, and an opaque one paints a black slab over it.
  let alpha = opaque
    ? CGImageAlphaInfo.noneSkipLast.rawValue
    : CGImageAlphaInfo.premultipliedLast.rawValue
  guard let context = CGContext(
    data: nil,
    width: Int(size.width), height: Int(size.height),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: alpha
  ) else { fail("could not make a \(Int(size.width))×\(Int(size.height)) context") }
  context.interpolationQuality = .high
  context.setAllowsAntialiasing(true)
  return context
}

func capturePath(_ scene: String, language: String) -> String {
  URL(fileURLWithPath: capturesDir)
    .appendingPathComponent(language)
    .appendingPathComponent("\(scene).png").path
}

func drawBackground(_ background: Background?, in context: CGContext, size: CGSize) {
  let frame = CGRect(origin: .zero, size: size)
  guard let background else {
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(frame)
    return
  }
  switch background.type ?? "solid" {
  case "gradient":
    let stops = (background.colors ?? []).map { color($0) }
    guard stops.count >= 2,
          let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: stops as CFArray, locations: nil)
    else { fail("a gradient background needs two or more colors") }
    let radians = ((background.angle ?? 90) - 90) * .pi / 180
    let reach = max(size.width, size.height)
    let dx = cos(radians) * reach / 2, dy = sin(radians) * reach / 2
    context.drawLinearGradient(
      gradient,
      start: CGPoint(x: frame.midX - dx, y: frame.midY - dy),
      end: CGPoint(x: frame.midX + dx, y: frame.midY + dy),
      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
  case "image":
    context.setFillColor(color(background.color ?? "#000000"))
    context.fill(frame)
    if let path = background.image, let image = images.image(resolve(path)) {
      context.draw(image, in: fitted(image, in: frame, fit: "cover"))
    }
  default:
    context.setFillColor(color(background.color ?? "#000000"))
    context.fill(frame)
  }
}

/// The device, with the capture inside it: a photographed `frame` when the model
/// names one, otherwise a rounded slab drawn in the bezel colour. Drawn is the
/// default because a bezel PNG is another binary asset that resamples
/// differently at every card size, and a drawn one is exact at any.
func drawDevice(
  _ layout: DeviceLayout, model: Device, capture: CGImage?,
  in context: CGContext, size: CGSize, travel: CGSize
) {
  // A photographed frame's aspect is the image's own; a drawn one declares it.
  var frameImage: CGImage?
  if let path = model.frame {
    frameImage = images.image(resolveFrame(path))
    if frameImage == nil { fail("no bezel at \(path)") }
  }
  let declared = frameImage.map { Double($0.width) / Double($0.height) } ?? model.aspect
  guard let aspect = declared else { fail("a device needs a frame or an aspect") }

  let width = size.width * layout.zoom / 100
  let height = width / aspect
  let x = centre(percent: layout.x ?? 50, span: width, travel: travel.width)
  // The storyboard measures from the top, the way a designer does; CoreGraphics
  // measures from the bottom. Converted once, here.
  let y = travel.height - centre(percent: layout.at, span: height, travel: travel.height)
  let body = CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)

  context.saveGState()
  context.translateBy(x: body.midX, y: body.midY)
  context.rotate(by: -(layout.rotate ?? 0) * .pi / 180)
  context.translateBy(x: -body.midX, y: -body.midY)

  // A photographed frame: the capture goes in the window first, the bezel over
  // it. The window is a percentage of the frame, so it scales with the zoom.
  if let frameImage {
    guard let window = model.screen else { fail("a frame needs a screen window") }
    let screen = CGRect(
      x: body.minX + body.width * window.left / 100,
      y: body.maxY - body.height * (window.top + window.height) / 100,
      width: body.width * window.width / 100,
      height: body.height * window.height / 100
    )
    context.saveGState()
    context.addPath(CGPath(
      roundedRect: screen,
      cornerWidth: body.width * window.radiusX / 100,
      cornerHeight: body.height * window.radiusY / 100,
      transform: nil))
    context.clip()
    if let capture {
      context.draw(capture, in: fitted(capture, in: screen, fit: "cover"))
    } else {
      context.setFillColor(CGColor(gray: 0.08, alpha: 1))
      context.fill(screen)
    }
    context.restoreGState()
    context.draw(frameImage, in: body)
    context.restoreGState()
    return
  }

  let radius = width * (model.radius ?? 0)
  let outline = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

  if let shadow = model.shadow, shadow > 0 {
    context.saveGState()
    context.setShadow(
      offset: CGSize(width: 0, height: -width * 0.02),
      blur: width * CGFloat(shadow),
      color: CGColor(gray: 0, alpha: 0.45)
    )
    context.setFillColor(color(model.color ?? "#000000"))
    context.addPath(outline)
    context.fillPath()
    context.restoreGState()
  }

  context.setFillColor(color(model.color ?? "#000000"))
  context.addPath(outline)
  context.fillPath()

  if let rim = model.rim {
    let hairline = max(width * 0.004, 1)
    let edge = body.insetBy(dx: hairline / 2, dy: hairline / 2)
    context.setStrokeColor(color(rim))
    context.setLineWidth(hairline)
    context.addPath(CGPath(
      roundedRect: edge, cornerWidth: radius - hairline / 2,
      cornerHeight: radius - hairline / 2, transform: nil))
    context.strokePath()
  }

  let inset = width * (model.bezel ?? 0)
  let screen = body.insetBy(dx: inset, dy: inset)
  // The screen's corner follows the body's rather than being a second number:
  // a constant inner radius reads as a differently-shaped phone at every zoom.
  let screenRadius = max(radius - inset, 0)
  context.saveGState()
  context.addPath(CGPath(
    roundedRect: screen, cornerWidth: screenRadius, cornerHeight: screenRadius, transform: nil))
  context.clip()
  if let capture {
    context.draw(capture, in: fitted(capture, in: screen, fit: "cover"))
  } else {
    context.setFillColor(CGColor(gray: 0.08, alpha: 1))
    context.fill(screen)
  }
  context.restoreGState()
  context.restoreGState()
}

/// The outline of a drawn element, and the clip a picture element gets. One
/// function so a tile and the art dropped on top of it cannot disagree about
/// where the corner is.
func outline(_ element: Element, in frame: CGRect, cardWidth: Double) -> CGPath {
  if element.shape == "ellipse" { return CGPath(ellipseIn: frame, transform: nil) }
  if let shape = element.shape, shape != "rect" { fail("no such shape: \(shape)") }
  let corner = cardWidth * (element.radius ?? 0) / 100
  guard corner > 0 else { return CGPath(rect: frame, transform: nil) }
  return CGPath(
    roundedRect: frame, cornerWidth: corner, cornerHeight: corner, transform: nil)
}

/// A drawn box. This and `drawText` are what let a card BUILD a piece of UI
/// rather than photograph one — a tile, a pill, a bubble — which is the only
/// way to make a detail bigger than it is on the device and still have it read
/// in ten languages.
func drawShape(_ element: Element, in frame: CGRect, context: CGContext, cardWidth: Double) {
  let path = outline(element, in: frame, cardWidth: cardWidth)
  if let fill = element.fill {
    context.addPath(path)
    context.setFillColor(color(fill))
    context.fillPath()
  }
  guard let stroke = element.stroke else { return }
  // Stroked INSIDE the box: clip to the outline and stroke at twice the width,
  // so the outer half is clipped away. A line centred on the path would put
  // half its width outside, and two boxes butted together would then overlap
  // by a whole line rather than sit edge to edge.
  let width = cardWidth * (element.strokeWidth ?? 0.15) / 100
  context.saveGState()
  context.addPath(path)
  context.clip()
  context.addPath(path)
  context.setStrokeColor(color(stroke))
  context.setLineWidth(width * 2)
  context.strokePath()
  context.restoreGState()
}

/// A localized paragraph, wrapped into the element's box. The caption block is
/// one CTLine per JSON line and cannot wrap; this is the other half of the
/// vocabulary — a string that has to fit inside a shape, in ten languages of
/// very different lengths.
func drawText(
  _ element: Element, _ text: Text, language: String, faces: [String: Face],
  in frame: CGRect, context: CGContext
) {
  let string = text(language)
  guard !string.isEmpty else { return }

  let size = element.size ?? 48
  let font = typefaces.font(
    faces[element.font ?? "display"], size: size,
    weight: element.weight ?? 700, language: language)

  let paragraph = NSMutableParagraphStyle()
  switch element.align {
  case "right": paragraph.alignment = .right
  case "center": paragraph.alignment = .center
  default: paragraph.alignment = .natural
  }
  // CoreText's lineSpacing is the GAP between lines, not the line box, so the
  // multiplier has to be turned into the extra. Passing 1.3 through directly
  // would make every value under 1 silently do nothing.
  paragraph.lineSpacing = size * ((element.lineHeight ?? 1.25) - 1)

  var attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: color(element.color ?? "#000000"),
    .paragraphStyle: paragraph,
  ]
  if let tracking = element.tracking, tracking != 0 {
    attributes[.kern] = tracking
  }

  let attributed = NSAttributedString(string: string, attributes: attributes)
  let setter = CTFramesetterCreateWithAttributedString(attributed)

  // CoreText fills a frame from its TOP edge downward, so aligning the block
  // vertically is done by moving that top edge rather than the block: the box
  // keeps its floor and loses the height the text does not need.
  var box = frame
  let wrapped = CTFramesetterSuggestFrameSizeWithConstraints(
    setter, CFRange(location: 0, length: 0), nil,
    CGSize(width: frame.width, height: .greatestFiniteMagnitude), nil)
  let slack = max(0, frame.height - ceil(wrapped.height))
  switch element.valign {
  case "middle": box.size.height -= slack / 2
  case "bottom": box.size.height -= slack
  default: break
  }

  let frameRef = CTFramesetterCreateFrame(
    setter, CFRange(location: 0, length: 0),
    CGPath(rect: box, transform: nil), nil)
  context.textMatrix = .identity
  CTFrameDraw(frameRef, context)

  // CTFrameDraw drops the lines that do not fit without a word, which is how a
  // set ships with half a sentence in the one language nobody on the team
  // reads. The card still renders — it just says so.
  let shown = CTFrameGetVisibleStringRange(frameRef)
  if shown.length < attributed.length {
    FileHandle.standardError.write(Data(
      "compose: \(language) text overflows its box — \"\(string)\"\n".utf8))
  }
}

func drawElement(
  _ element: Element, language: String, faces: [String: Face],
  in context: CGContext, size: CGSize
) {
  let frame = CGRect(
    x: size.width * element.x / 100,
    y: size.height - size.height * element.y / 100 - size.height * element.height / 100,
    width: size.width * element.width / 100,
    height: size.height * element.height / 100
  )
  context.saveGState()
  defer { context.restoreGState() }
  if let rotate = element.rotate, rotate != 0 {
    context.translateBy(x: frame.midX, y: frame.midY)
    context.rotate(by: -rotate * .pi / 180)
    context.translateBy(x: -frame.midX, y: -frame.midY)
  }

  if let text = element.text {
    drawText(element, text, language: language, faces: faces, in: frame, context: context)
    return
  }
  // `shape` may be left out when `fill` or `stroke` already says what this is:
  // a rounded rect is the only one anybody writes, and naming it twice is noise.
  if element.shape != nil || element.fill != nil || element.stroke != nil {
    drawShape(element, in: frame, context: context, cardWidth: size.width)
    return
  }

  let path: String
  if let localized = element.localized?[language] {
    path = resolve(localized)
  } else if let scene = element.scene {
    path = capturePath(scene, language: language)
  } else if let image = element.image {
    path = resolve(image)
  } else {
    fail("an element needs a scene, an image, a shape or a text")
  }
  guard let image = images.image(path) else {
    FileHandle.standardError.write(Data("compose: missing art \(path)\n".utf8))
    return
  }
  if let radius = element.radius, radius > 0 {
    context.addPath(outline(element, in: frame, cardWidth: size.width))
    context.clip()
  }
  context.draw(image, in: fitted(image, in: frame, fit: element.fit ?? "cover"))
}

/// The caption block, centred on `at` and laid out downward from there. Each
/// line is one CTLine, so a line that mixes Latin and Han is shaped once with
/// the cascade rather than measured twice.
func drawCaption(
  _ caption: Caption, language: String, faces: [String: Face],
  in context: CGContext, size: CGSize
) {
  struct Laid {
    let line: CTLine
    let width: Double
    let height: Double
    let ascent: Double
    let align: String
  }

  var laid: [Laid] = []
  for line in caption.lines {
    let text = line.text(language)
    guard !text.isEmpty else { continue }
    let font = typefaces.font(
      faces[line.font ?? "display"], size: line.size,
      weight: line.weight ?? 700, language: language)
    var attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color(line.color),
    ]
    if let tracking = line.tracking, tracking != 0 {
      attributes[.kern] = tracking
    }
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let ctLine = CTLineCreateWithAttributedString(attributed)
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let width = CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading)
    laid.append(Laid(
      line: ctLine, width: width,
      height: line.size * (line.lineHeight ?? 1.15),
      ascent: ascent, align: line.align ?? "center"
    ))
  }
  guard !laid.isEmpty else { return }

  let block = laid.reduce(0) { $0 + $1.height }
  let inset = size.width * (caption.inset ?? 6) / 100
  var top = size.height - size.height * caption.at / 100 + block / 2

  for entry in laid {
    let x: Double
    switch entry.align {
    case "left": x = inset
    case "right": x = size.width - inset - entry.width
    default: x = (size.width - entry.width) / 2
    }
    // The baseline sits one ascent below the line box's top, so lines of
    // different sizes in one block still share a rhythm.
    context.textPosition = CGPoint(x: x, y: top - entry.ascent)
    CTLineDraw(entry.line, context)
    top -= entry.height
  }
}

// ============================================================================
// A locale's set
// ============================================================================

func captureImage(_ layout: DeviceLayout, language: String) -> CGImage? {
  if let image = layout.image { return images.image(resolve(image)) }
  guard let scene = layout.scene else { return nil }
  let path = capturePath(scene, language: language)
  if let found = images.image(path) { return found }
  FileHandle.standardError.write(Data("compose: no capture at \(path)\n".utf8))
  return nil
}

func write(_ image: CGImage, to path: String) {
  let url = URL(fileURLWithPath: path)
  try? FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { fail("cannot write \(path)") }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fail("cannot finalize \(path)") }
}

/// Every device on a card, drawn in layer order onto a canvas that may be wider
/// than the card. A spanning pair renders its devices once, on a canvas two
/// cards wide, and each card takes its half — which is what makes the two
/// halves line up exactly, rather than to within a rounding of a rotation.
func drawDevices(
  lead: Card, language: String, in context: CGContext,
  size: CGSize, travel: CGSize, offset: Double
) {
  var layouts: [DeviceLayout] = []
  if let device = lead.device { layouts.append(device) }
  layouts.append(contentsOf: lead.extraDevices ?? [])
  layouts.sort { ($0.layer ?? 0) < ($1.layer ?? 0) }
  guard !layouts.isEmpty else { return }

  let canvas = newContext(travel, opaque: false)
  canvas.clear(CGRect(origin: .zero, size: travel))
  for layout in layouts {
    let name = layout.model ?? storyboard.defaultDevice ?? "phone"
    guard let model = storyboard.devices?[name] else { fail("no device model '\(name)'") }
    drawDevice(
      layout, model: model, capture: captureImage(layout, language: language),
      in: canvas, size: size, travel: travel)
  }
  guard let rendered = canvas.makeImage() else { return }
  context.draw(
    rendered,
    in: CGRect(x: -offset, y: 0, width: travel.width, height: travel.height))
}

/// The first card of each span, by position — the one that holds the shared
/// device's layout. Computed once rather than searched by name, because two
/// cards in a set may legitimately be called the same thing in two spans.
let spanLeads: [String: Int] = {
  var leads: [String: Int] = [:]
  for (position, card) in storyboard.cards.enumerated() {
    if let span = card.span, leads[span] == nil { leads[span] = position }
  }
  return leads
}()

func render(locale: Storyboard.Locale) {
  let faces = storyboard.fonts ?? [:]
  var index = 0

  var counters: [String: Int] = [:]
  var written = 0
  for (position, card) in storyboard.cards.enumerated() {
    if card.skip?.contains(locale.capture) == true { continue }
    let folder = card.dir ?? ""
    counters[folder, default: 0] += 1
    index = counters[folder]!
    guard wanted(card, number: index) else { continue }
    let cardSize = card.size.map { CGSize(width: $0.width, height: $0.height) } ?? defaultCardSize

    let context = newContext(cardSize)
    drawBackground(card.background, in: context, size: cardSize)

    // A spanning card's devices come from the lead, on a canvas as wide as the
    // pair; a plain card's travel is itself.
    var lead = card
    var travel = cardSize
    var offset: Double = 0
    if let span = card.span, let leadPosition = spanLeads[span] {
      lead = storyboard.cards[leadPosition]
      travel = CGSize(width: cardSize.width * 2, height: cardSize.height)
      offset = position == leadPosition ? 0 : cardSize.width
    }
    drawDevices(
      lead: lead, language: locale.capture, in: context,
      size: cardSize, travel: travel, offset: offset)

    for element in card.elements ?? [] {
      drawElement(
        element, language: locale.capture, faces: faces, in: context, size: cardSize)
    }
    if let caption = card.caption {
      drawCaption(caption, language: locale.capture, faces: faces, in: context, size: cardSize)
    }

    guard let image = context.makeImage() else { fail("could not render \(card.name)") }
    let file = String(format: "%02d-%@.png", index, card.name)
    var destination = URL(fileURLWithPath: outDir).appendingPathComponent(locale.out)
    if !folder.isEmpty { destination.appendPathComponent(folder) }
    write(image, to: destination.appendingPathComponent(file).path)
    written += 1
  }
  // What was written, not what the storyboard holds: under `--card` the two
  // differ, and the tally is the only thing saying which cards a run touched.
  FileHandle.standardError.write(Data("==>   \(locale.out) \(written) cards\n".utf8))
}

var locales = storyboard.locales
if !onlyLocales.isEmpty {
  locales = locales.filter { onlyLocales.contains($0.capture) || onlyLocales.contains($0.out) }
  guard !locales.isEmpty else { fail("no such locale in the storyboard") }
}

// Serial, on purpose: the locales are fanned out one process each by the
// caller. Drawing them on threads inside one process meant every drawing
// function had to be `@Sendable` to satisfy strict concurrency, for a win a
// second process gets for free — and a locale that crashes then takes the whole
// set with it rather than one folder.
for locale in locales {
  render(locale: locale)
}
