import CoreGraphics

public enum VisionGeometry {
    /// Converts a Vision normalized rect (origin bottom-left, 0...1) to image pixels with a top-left origin.
    public static func pixelRect(fromNormalized r: CGRect, imageWidth w: Int, imageHeight h: Int) -> CGRect {
        let W = CGFloat(w), H = CGFloat(h)
        return CGRect(x: r.minX * W, y: (1 - r.minY - r.height) * H, width: r.width * W, height: r.height * H)
    }
}
