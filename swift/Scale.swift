// Generated from ios-kit/swift/Scale.swift — do not edit here.
// Edit it in ../ios-kit and run `.kit/scripts/kit sync`.

import CoreGraphics

/// Tailwind's size ladder, in points: one step is 4pt, and the name is the
/// Tailwind unit (`s1_5` is `1.5` is 6pt).
///
/// This is the raw ladder and nothing else. What a rung is *called* — a gap, an
/// inset, a corner — is each app's own `Spacing` and `Radii`, which name these
/// values rather than restating them. The split is deliberate: before the kit,
/// all three apps had a `Spacing.lg`, and it meant 10pt in one and 16pt in
/// another. Sharing the numbers under shared names would have moved layout in
/// shipped apps; sharing the ladder cannot.
enum Scale {
  /// Flush.
  static let s0: CGFloat = 0
  /// 0.25 — a hairline gap.
  static let s0_25: CGFloat = 1
  /// 0.5
  static let s0_5: CGFloat = 2
  /// 1
  static let s1: CGFloat = 4
  /// 1.5
  static let s1_5: CGFloat = 6
  /// 2
  static let s2: CGFloat = 8
  /// 2.5
  static let s2_5: CGFloat = 10
  /// 3
  static let s3: CGFloat = 12
  /// 3.5
  static let s3_5: CGFloat = 14
  /// 4 — the usual panel inset.
  static let s4: CGFloat = 16
  /// 5
  static let s5: CGFloat = 20
  /// 6 — the usual dialog inset.
  static let s6: CGFloat = 24
  /// 7
  static let s7: CGFloat = 28
  /// 8
  static let s8: CGFloat = 32
  /// 10
  static let s10: CGFloat = 40
  /// 12
  static let s12: CGFloat = 48
  /// 14
  static let s14: CGFloat = 56
}
