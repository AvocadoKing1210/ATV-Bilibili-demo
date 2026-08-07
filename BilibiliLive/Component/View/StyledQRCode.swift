//
//  StyledQRCode.swift
//  BilibiliLive
//
//  CIQRCodeGenerator hands back a bitmap of hard squares. That is the correct
//  code and an ugly picture, so this reads the module matrix back out of it
//  and re-draws the same modules as connected rounded blobs — the Instagram /
//  WeChat nametag treatment — with bilibili's own eyes and mark on top.
//
//  Nothing here changes which modules are dark, so the result scans exactly as
//  well as the plain one. The centre mark is affordable because the code is
//  generated at correction level H (30% recoverable) and the badge covers
//  under 5% of the symbol's area.
//

import CoreImage
import UIKit

enum StyledQRCode {
    struct Style {
        /// Data modules. Near-black rather than pink: scanners key off
        /// luminance contrast, and bilibili pink on white is only ~2.8:1.
        var moduleColor = UIColor(rgb: 0x16_16_1A)
        /// The three finder patterns. Brand colour lives here, where it costs
        /// nothing — a scanner locates these by shape, and they stay the
        /// darkest thing on the card either way.
        var eyeColor = UIColor.bilipink
        var background = UIColor.white
        var cornerRadius: CGFloat = 56
        /// Quiet zone, in modules. The spec's minimum is 4.
        var quietZone: CGFloat = 4
        /// bilibili mark punched into the centre.
        var showsMark = true
        /// Q recovers 25% — six times what the centre mark costs, and it buys
        /// back four versions' worth of modules against H. Fewer, fatter
        /// modules are the whole reason the rounding reads at ten feet: the
        /// login URL at H is a 53-module symbol whose blobs are too small to
        /// see, at Q it is 45.
        var correctionLevel = "Q"
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: true])

    static func image(for text: String, size: CGFloat, style: Style = Style()) -> UIImage? {
        guard let matrix = matrix(for: text, correctionLevel: style.correctionLevel) else { return nil }
        let count = matrix.count
        let module = size / (CGFloat(count) + style.quietZone * 2)
        let origin = CGPoint(x: module * style.quietZone, y: module * style.quietZone)

        func isDark(_ row: Int, _ col: Int) -> Bool {
            guard row >= 0, row < count, col >= 0, col < count else { return false }
            return matrix[row][col]
        }
        // The finder patterns are drawn as whole shapes, so the data pass has
        // to leave their 7x7 blocks alone — and treat them as empty when
        // deciding whether a neighbouring data module should round off.
        func isFinder(_ row: Int, _ col: Int) -> Bool {
            (row < 7 && col < 7) || (row < 7 && col >= count - 7) || (row >= count - 7 && col < 7)
        }
        func isData(_ row: Int, _ col: Int) -> Bool {
            isDark(row, col) && !isFinder(row, col)
        }

        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let card = CGRect(x: 0, y: 0, width: size, height: size)
            style.background.setFill()
            UIBezierPath(roundedRect: card, cornerRadius: style.cornerRadius).fill()

            style.moduleColor.setFill()
            for row in 0..<count {
                for col in 0..<count where isData(row, col) {
                    let rect = CGRect(x: origin.x + CGFloat(col) * module,
                                      y: origin.y + CGFloat(row) * module,
                                      width: module, height: module)
                    // A corner rounds only where both of its edges are open.
                    // That is what turns a run of squares into one capsule and
                    // an isolated square into a dot.
                    let up = isData(row - 1, col), down = isData(row + 1, col)
                    let left = isData(row, col - 1), right = isData(row, col + 1)
                    modulePath(rect: rect,
                               radius: module / 2,
                               topLeft: !up && !left,
                               topRight: !up && !right,
                               bottomRight: !down && !right,
                               bottomLeft: !down && !left).fill()
                }
            }

            for corner in [(0, 0), (0, count - 7), (count - 7, 0)] {
                drawFinder(row: corner.0, col: corner.1,
                           origin: origin, module: module, color: style.eyeColor)
            }

            if style.showsMark {
                drawMark(in: card, style: style)
            }
        }
    }

    // MARK: - Matrix

    /// The dark-module matrix, quiet zone trimmed off. Row 0 is the top of the
    /// symbol — the three finder patterns pin the bounding box to the symbol's
    /// true edges, so trimming is exact rather than an assumption about how
    /// wide a border CIQRCodeGenerator happens to add.
    static func matrix(for text: String, correctionLevel: String = "Q") -> [[Bool]]? {
        guard let data = text.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator")
        else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else { return nil }
        let extent = output.extent.integral
        guard !extent.isEmpty else { return nil }
        let width = Int(extent.width), height = Int(extent.height)
        guard let cgImage = ciContext.createCGImage(output, from: extent) else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .none
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let count = max(maxX - minX, maxY - minY) + 1

        return (0..<count).map { row in
            (0..<count).map { col in
                let x = minX + col, y = minY + row
                guard x < width, y < height else { return false }
                return pixels[y * width + x] < 128
            }
        }
    }

    // MARK: - Drawing

    private static func modulePath(rect: CGRect, radius: CGFloat,
                                   topLeft: Bool, topRight: Bool,
                                   bottomRight: Bool, bottomLeft: Bool) -> UIBezierPath
    {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + (topLeft ? radius : 0), y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - (topRight ? radius : 0), y: rect.minY))
        if topRight {
            path.addArc(withCenter: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                        radius: radius, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - (bottomRight ? radius : 0)))
        if bottomRight {
            path.addArc(withCenter: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                        radius: radius, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.minX + (bottomLeft ? radius : 0), y: rect.maxY))
        if bottomLeft {
            path.addArc(withCenter: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                        radius: radius, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + (topLeft ? radius : 0)))
        if topLeft {
            path.addArc(withCenter: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                        radius: radius, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        }
        path.close()
        return path
    }

    /// A finder pattern is always the same 7x7: a one-module ring on the
    /// outside, a 3x3 block in the middle. Drawing it as two rounded shapes
    /// instead of 33 squares is what makes the code read as designed.
    private static func drawFinder(row: Int, col: Int, origin: CGPoint,
                                   module: CGFloat, color: UIColor)
    {
        let block = CGRect(x: origin.x + CGFloat(col) * module,
                           y: origin.y + CGFloat(row) * module,
                           width: module * 7, height: module * 7)
        color.setStroke()
        let ring = UIBezierPath(roundedRect: block.insetBy(dx: module / 2, dy: module / 2),
                                cornerRadius: module * 1.7)
        ring.lineWidth = module
        ring.stroke()

        color.setFill()
        UIBezierPath(roundedRect: CGRect(x: block.minX + module * 2, y: block.minY + module * 2,
                                         width: module * 3, height: module * 3),
                     cornerRadius: module * 0.9).fill()
    }

    private static func drawMark(in card: CGRect, style: Style) {
        let badge = CGRect(x: 0, y: 0, width: card.width * 0.19, height: card.width * 0.19)
            .offsetBy(dx: card.midX - card.width * 0.095, dy: card.midY - card.width * 0.095)
        style.background.setFill()
        UIBezierPath(ovalIn: badge).fill()
        BiliMark.draw(in: badge.insetBy(dx: badge.width * 0.14, dy: badge.width * 0.14),
                      color: style.eyeColor)
    }
}
