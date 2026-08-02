// The CGWindowID of an app's front document window, for `screencapture -l`.
//
// A Mac store card is a picture of a WINDOW, not of a screen: a screen capture
// carries your desktop and your menu bar into the shot, and it comes out at
// whatever size this particular Mac's panel is — so the same set shot on a 14"
// and on a Studio Display are two different pictures. A window is the same
// pixels on both.
//
//   window-id <bundle-id>   -> the window number, on stdout
//
// Exit codes are distinct because the three failures want different advice:
// 3 is "the app is not running", 1 is "it is running but has no window yet"
// (the usual one — the settle in scripts/scenes.sh is too short, or the app is
// LSUIElement and has none at all), and 2/4 are misuse.

import AppKit
import CoreGraphics

guard let bundleID = CommandLine.arguments.dropFirst().first else {
  FileHandle.standardError.write(Data("usage: window-id <bundle-id>\n".utf8))
  exit(2)
}

guard
  let pid = NSRunningApplication
    .runningApplications(withBundleIdentifier: bundleID)
    .first?
    .processIdentifier
else {
  FileHandle.standardError.write(Data("no running app with bundle id \(bundleID)\n".utf8))
  exit(3)
}

guard
  let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
  ) as? [[String: Any]]
else {
  FileHandle.standardError.write(Data("could not read the window list\n".utf8))
  exit(4)
}

// Front to back, which is the order CGWindowListCopyWindowInfo returns, so the
// first match is the one a person would call "the window".
for window in windows {
  guard
    let owner = window[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
    let number = window[kCGWindowNumber as String] as? CGWindowID
  else { continue }

  // Layer 0 is the normal window level. Anything above it is a panel, a status
  // item, or a floating overlay — a recorder's control bar, say, which is on
  // screen the whole time and would be photographed instead of the app.
  guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }

  // Toolbars and shadows show up as their own tiny windows on some macOS
  // versions. Nothing a store card wants is smaller than this.
  if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
    let width = bounds["Width"], let height = bounds["Height"],
    width < 64 || height < 64
  {
    continue
  }

  print(number)
  exit(0)
}

FileHandle.standardError.write(Data("\(bundleID) is running but has no ordinary window\n".utf8))
exit(1)
