import CoreGraphics

/// Conversion between global Quartz coordinates (top-left origin, y down; Core, AX,
/// CGWindowList, CGEvent) and AppKit screen coordinates (bottom-left origin of the
/// primary display, y up; NSWindow, NSScreen). `primaryHeight` is the height of the
/// primary display (`NSScreen.screens[0].frame.height`).
public enum Geometry {
    public static func appKitRect(fromQuartz rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func quartzRect(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func appKitPoint(fromQuartz point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    public static func quartzPoint(fromAppKit point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
