// Generated from ios-kit/swift/Opacity.swift — do not edit here.
// Edit it in ../ios-kit and run `.kit/scripts/kit sync`.

import CoreGraphics

/// The alpha ladder for tinted fills, scrims and overlays. A small, deliberate
/// set of steps so opacity reads as intent (`.strong` scrim, `.faint` fill)
/// rather than as a scattering of one-off decimals: write
/// `color.opacity(Opacity.soft)`, never `color.opacity(0.24)`.
///
/// Bare `.opacity(0)` / `.opacity(1)` for show-and-hide is not an alpha choice
/// and stays a literal.
enum Opacity {
  static let faint = 0.08
  static let light = 0.15
  static let soft = 0.25
  static let medium = 0.4
  static let half = 0.5
  static let strong = 0.7
  static let heavy = 0.85
}
