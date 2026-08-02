#!/usr/bin/env swift

// Says which of two PNGs are the same PICTURE, which is not the same thing as
// the same bytes. The simulator lays a faint dither over the glass and the
// felt, so two captures of a screen nobody touched come back differing by one
// or two levels in a few thousand pixels — invisible on any display, and enough
// to rewrite a store card and put it in `git status`.
//
// Reads `old<TAB>new` pairs on stdin and prints the `new` paths whose picture
// did not change, one per line, for the caller to put back.
//
//   printf 'a.png\tb.png\n' | swift scripts/same-picture.swift --tolerance 3
//
// The tolerance is a per-channel ceiling, not an average: one pixel a whole
// level out of range is a real change and reports as one. 3/255 is a little
// under what a display can resolve on this cloth; anything a reviewer could
// see is far above it.

import CoreGraphics
import Foundation
import ImageIO

var tolerance = 3
var arguments = Array(CommandLine.arguments.dropFirst())
while let index = arguments.firstIndex(of: "--tolerance") {
  guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value >= 0 else {
    FileHandle.standardError.write(Data("error: --tolerance needs a number\n".utf8))
    exit(2)
  }
  tolerance = value
  arguments.removeSubrange(index ... (index + 1))
}

/// Decoded into one known layout — whatever a PNG says about its colour space
/// or its alpha, both sides are compared as the same 8-bit RGB.
func pixels(_ path: String) -> (bytes: [UInt8], width: Int, height: Int)? {
  guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { return nil }
  let width = image.width, height = image.height
  var bytes = [UInt8](repeating: 0, count: width * height * 4)
  let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
    guard let context = CGContext(
      data: raw.baseAddress,
      width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
  }
  return ok ? (bytes, width, height) : nil
}

/// Nil when either file won't decode — the caller then treats the pair as
/// changed, since a card it cannot read is not one it may quietly keep.
///
/// Row by row, and a row that matches byte for byte is skipped whole: this runs
/// interpreted, over forty pairs of three-megapixel cards, and the dither it is
/// looking for touches a fraction of one card's rows.
func samePicture(_ old: String, _ new: String) -> Bool? {
  guard let a = pixels(old), let b = pixels(new) else { return nil }
  guard a.width == b.width, a.height == b.height else { return false }
  let stride = a.width * 4
  return a.bytes.withUnsafeBufferPointer { left in
    b.bytes.withUnsafeBufferPointer { right in
      guard let l = left.baseAddress, let r = right.baseAddress else { return false }
      for row in 0 ..< a.height {
        let start = row * stride
        if memcmp(l + start, r + start, stride) == 0 {
          continue
        }
        for index in Swift.stride(from: start, to: start + stride, by: 4) {
          for channel in 0 ..< 3
            where abs(Int(left[index + channel]) - Int(right[index + channel])) > tolerance
          {
            return false
          }
        }
      }
      return true
    }
  }
}

while let line = readLine(strippingNewline: true) {
  let pair = line.split(separator: "\t", maxSplits: 1).map(String.init)
  guard pair.count == 2 else { continue }
  if samePicture(pair[0], pair[1]) == true {
    print(pair[1])
  }
}
