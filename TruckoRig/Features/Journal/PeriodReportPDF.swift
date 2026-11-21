import UIKit

/// Midnight & Gold PDF of a period report. One table per load, drawn on device.
enum PeriodReportPDF {

    static let pageSize = CGSize(width: 595.2, height: 841.8)

    static func data(for report: PeriodReport) -> Data {
        let bytes = NSMutableData()
        let bounds = CGRect(origin: .zero, size: pageSize)
        let info: [String: Any] = [
            kCGPDFContextTitle as String: report.periodTitle,
            kCGPDFContextCreator as String: report.brand,
            kCGPDFContextAuthor as String: report.driverName ?? report.brand,
        ]
        UIGraphicsBeginPDFContextToData(bytes, bounds, info)
        Canvas(report: report, page: bounds).draw()
        UIGraphicsEndPDFContext()
        return bytes as Data
    }
}

private final class Canvas {
    let report: PeriodReport
    let page: CGRect
    let margin: CGFloat = 36
    let footerReserve: CGFloat = 32
    var y: CGFloat = 0
    var pageOpen = false

    init(report: PeriodReport, page: CGRect) {
        self.report = report
        self.page = page
    }

    var contentWidth: CGFloat { page.width - margin * 2 }
    var contentBottom: CGFloat { page.height - footerReserve }

    func draw() {
        beginPage(continuation: false)
        drawHeaderBand()
        drawSectionTitle(report.summaryTitle)
        drawSummaryCard()
        drawSectionTitle(report.loadsTitle)
        if report.loads.isEmpty {
            drawNoteCard(report.emptyLoadsMessage)
        } else {
            for load in report.loads {
                drawLoadCard(load)
            }
        }
        drawPageFooter()
    }

    func beginPage(continuation: Bool) {
        if pageOpen {
            drawPageFooter()
        }
        UIGraphicsBeginPDFPage()
        pageOpen = true
        Palette.page.setFill()
        UIRectFill(page)
        if continuation {
            drawContinuationBar()
        } else {
            y = 0
        }
    }

    func ensure(_ height: CGFloat) {
        if y + height > contentBottom {
            beginPage(continuation: true)
        }
    }

    func drawHeaderBand() {
        let textWidth = contentWidth
        let brandHeight = measure(report.brand, width: textWidth, font: Palette.brandFont)
        var block: [(String, UIFont, UIColor)] = []
        if let driver = report.driverName {
            block.append(("\(report.driverLabel): \(driver)", Palette.headerFont, Palette.cream))
        }
        block.append(("\(report.periodLabel): \(report.periodTitle)", Palette.headerFont, Palette.cream))
        block.append(("\(report.generatedLabel): \(report.generatedOn)", Palette.headerMutedFont, Palette.creamMuted))
        let body = block.reduce(CGFloat(0)) { $0 + measure($1.0, width: textWidth, font: $1.1) + 4 }
        let height = 28 + brandHeight + 8 + body + 16
        let band = CGRect(x: 0, y: 0, width: page.width, height: height)
        Palette.midnight.setFill()
        UIRectFill(band)
        Palette.midnightDeep.setFill()
        UIRectFill(CGRect(x: page.width * 0.55, y: 0, width: page.width * 0.45, height: height))
        var cursor = CGFloat(28)
        cursor += draw(report.brand, x: margin, y: cursor, width: textWidth, font: Palette.brandFont, color: Palette.gold) + 8
        for (text, font, color) in block {
            cursor += draw(text, x: margin, y: cursor, width: textWidth, font: font, color: color) + 4
        }
        Palette.gold.setFill()
        UIRectFill(CGRect(x: 0, y: height - 4, width: page.width, height: 4))
        y = height + 20
    }

    func drawContinuationBar() {
        let height: CGFloat = 36
        Palette.midnight.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: page.width, height: height))
        Palette.gold.setFill()
        UIRectFill(CGRect(x: 0, y: height - 3, width: page.width, height: 3))
        _ = draw(
            "\(report.brand)  ·  \(report.periodTitle)",
            x: margin,
            y: 10,
            width: contentWidth,
            font: Palette.headerFont,
            color: Palette.cream
        )
        y = height + 16
    }

    func drawSectionTitle(_ title: String) {
        let height = measure(title, width: contentWidth, font: Palette.sectionFont) + 10
        ensure(height + 8)
        _ = draw(title, x: margin, y: y, width: contentWidth, font: Palette.sectionFont, color: Palette.ink)
        let underline = measure(title, width: contentWidth, font: Palette.sectionFont)
        Palette.gold.setFill()
        UIRectFill(CGRect(x: margin, y: y + underline + 2, width: min(72, underline), height: 2))
        y += height + 8
    }

    func drawSummaryCard() {
        let rows = report.summary
        let rowHeights = rows.map { rowHeight($0) }
        let cardHeight = 8 + rowHeights.reduce(0, +)
        ensure(min(cardHeight, 80))
        drawTable(rows: rows, rowHeights: rowHeights, accent: true)
    }

    func drawLoadCard(_ load: PeriodReportLoadBlock) {
        let titleHeight = measure(load.title, width: contentWidth - 80, font: Palette.loadTitleFont)
        let rowHeights = load.lines.map { rowHeight($0) }
        let cardHeight = 14 + titleHeight + 8 + rowHeights.reduce(0, +) + 6
        if y + cardHeight > contentBottom && y > margin + 40 {
            beginPage(continuation: true)
        }
        if y + cardHeight <= contentBottom {
            drawLoadBox(load, titleHeight: titleHeight, rowHeights: rowHeights, fullHeight: cardHeight)
            y += 12
            return
        }
        drawLoadBox(load, titleHeight: titleHeight, rowHeights: [], fullHeight: 14 + titleHeight + 8)
        var remaining = load.lines
        var heights = rowHeights
        while !remaining.isEmpty {
            ensure(heights[0] + 8)
            let room = contentBottom - y - 8
            var count = 0
            var used: CGFloat = 0
            while count < remaining.count && used + heights[count] <= room {
                used += heights[count]
                count += 1
            }
            if count == 0 { count = 1 }
            let slice = Array(remaining.prefix(count))
            let sliceHeights = Array(heights.prefix(count))
            drawTable(rows: slice, rowHeights: sliceHeights, accent: false)
            remaining.removeFirst(count)
            heights.removeFirst(count)
        }
        y += 12
    }

    func drawLoadBox(
        _ load: PeriodReportLoadBlock,
        titleHeight: CGFloat,
        rowHeights: [CGFloat],
        fullHeight: CGFloat
    ) {
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: fullHeight)
        Palette.card.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
        Palette.gold.setFill()
        UIRectFill(CGRect(x: rect.minX, y: rect.minY, width: 4, height: rect.height))
        let badge = "\(load.number)"
        let badgeWidth = measureWidth(badge, font: Palette.badgeFont)
        let badgeRect = CGRect(x: rect.minX + 14, y: rect.minY + 12, width: badgeWidth + 14, height: 18)
        Palette.gold.setFill()
        UIBezierPath(roundedRect: badgeRect, cornerRadius: 4).fill()
        _ = draw(badge, x: badgeRect.minX + 7, y: badgeRect.minY + 1, width: badgeWidth + 2, font: Palette.badgeFont, color: Palette.espresso)
        _ = draw(
            load.title,
            x: badgeRect.maxX + 8,
            y: rect.minY + 12,
            width: rect.maxX - badgeRect.maxX - 20,
            font: Palette.loadTitleFont,
            color: Palette.ink
        )
        y = rect.minY + 14 + titleHeight + 8
        guard !rowHeights.isEmpty else { return }
        drawRows(load.lines, heights: rowHeights, inset: true)
        y = rect.maxY
    }

    func drawTable(rows: [PeriodReportLine], rowHeights: [CGFloat], accent: Bool) {
        let height = 8 + rowHeights.reduce(0, +)
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: height)
        Palette.card.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
        if accent {
            Palette.gold.setFill()
            UIRectFill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 3))
        }
        y = rect.minY + (accent ? 8 : 4)
        drawRows(rows, heights: rowHeights, inset: true)
        y = rect.maxY + 12
    }

    func drawRows(_ rows: [PeriodReportLine], heights: [CGFloat], inset: Bool) {
        let x = margin + (inset ? 14 : 0)
        let width = contentWidth - (inset ? 28 : 0)
        let labelWidth = min(180, width * 0.42)
        for (index, row) in rows.enumerated() {
            if index > 0 {
                Palette.divider.setFill()
                UIRectFill(CGRect(x: x, y: y, width: width, height: 0.6))
            }
            let rowHeight = heights[index]
            _ = draw(row.label, x: x, y: y + 5, width: labelWidth - 8, font: Palette.labelFont, color: Palette.secondary)
            _ = draw(row.value, x: x + labelWidth, y: y + 5, width: width - labelWidth, font: Palette.valueFont, color: Palette.ink)
            y += rowHeight
        }
    }

    func drawNoteCard(_ message: String) {
        let height = measure(message, width: contentWidth - 28, font: Palette.valueFont) + 24
        ensure(height)
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: height)
        Palette.card.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
        _ = draw(message, x: rect.minX + 14, y: rect.minY + 12, width: contentWidth - 28, font: Palette.valueFont, color: Palette.secondary)
        y = rect.maxY + 12
    }

    func drawPageFooter() {
        let baseline = page.height - 22
        Palette.divider.setFill()
        UIRectFill(CGRect(x: margin, y: baseline - 8, width: contentWidth, height: 0.6))
        _ = draw(report.footer, x: margin, y: baseline - 4, width: contentWidth, font: Palette.footerFont, color: Palette.secondary)
    }

    func rowHeight(_ row: PeriodReportLine) -> CGFloat {
        let width = contentWidth - 28
        let labelWidth = min(180, width * 0.42)
        let label = measure(row.label, width: labelWidth - 8, font: Palette.labelFont)
        let value = measure(row.value, width: width - labelWidth, font: Palette.valueFont)
        return max(label, value) + 12
    }

    @discardableResult
    func draw(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, font: UIFont, color: UIColor) -> CGFloat {
        let height = measure(text, width: width, font: font)
        let style = paragraph
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let rect = CGRect(x: x, y: y, width: width, height: height)
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        return height
    }

    func measureWidth(_ text: String, font: UIFont) -> CGFloat {
        let size = (text as NSString).size(withAttributes: [.font: font])
        return ceil(size.width)
    }

    func measure(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
        ]
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return ceil(bounds.height)
    }

    var paragraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        return style
    }
}

private enum Palette {
    static let midnight = UIColor(red: 0x1E / 255, green: 0x21 / 255, blue: 0x50 / 255, alpha: 1)
    static let midnightDeep = UIColor(red: 0x0F / 255, green: 0x12 / 255, blue: 0x30 / 255, alpha: 1)
    static let gold = UIColor(red: 0xC8 / 255, green: 0xA8 / 255, blue: 0x67 / 255, alpha: 1)
    static let cream = UIColor(red: 0xF7 / 255, green: 0xF2 / 255, blue: 0xE6 / 255, alpha: 1)
    static let creamMuted = UIColor(red: 0xD9 / 255, green: 0xCF / 255, blue: 0xB4 / 255, alpha: 1)
    static let page = UIColor(red: 0xF5 / 255, green: 0xF4 / 255, blue: 0xF1 / 255, alpha: 1)
    static let card = UIColor(red: 0xFD / 255, green: 0xFC / 255, blue: 0xFA / 255, alpha: 1)
    static let ink = UIColor(red: 0x16 / 255, green: 0x18 / 255, blue: 0x2B / 255, alpha: 1)
    static let secondary = UIColor(red: 0x58 / 255, green: 0x5A / 255, blue: 0x6E / 255, alpha: 1)
    static let divider = UIColor(red: 0xE6 / 255, green: 0xE2 / 255, blue: 0xD8 / 255, alpha: 1)
    static let espresso = UIColor(red: 0x1D / 255, green: 0x17 / 255, blue: 0x08 / 255, alpha: 1)

    static let brandFont = UIFont.systemFont(ofSize: 22, weight: .bold)
    static let headerFont = UIFont.systemFont(ofSize: 12, weight: .medium)
    static let headerMutedFont = UIFont.systemFont(ofSize: 11, weight: .regular)
    static let sectionFont = UIFont.systemFont(ofSize: 14, weight: .bold)
    static let labelFont = UIFont.systemFont(ofSize: 10, weight: .regular)
    static let valueFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
    static let loadTitleFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
    static let badgeFont = UIFont.systemFont(ofSize: 11, weight: .bold)
    static let footerFont = UIFont.systemFont(ofSize: 9, weight: .medium)
}
