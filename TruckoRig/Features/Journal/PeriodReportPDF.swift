import UIKit

/// US Letter load statement. White page, grey table header, one row per load.
///
/// Fuel, expenses, and carrier deductions are not on this page. The plain-text share
/// still includes them.
enum PeriodReportPDF {

    static let pageSize = CGSize(width: 612, height: 792)

    static func data(for report: PeriodReport) -> Data {
        let bytes = NSMutableData()
        let bounds = CGRect(origin: .zero, size: pageSize)
        let statement = PeriodReportStatementBuilder.make(report)
        let info: [String: Any] = [
            kCGPDFContextTitle as String: statement.title,
            kCGPDFContextCreator as String: report.brand,
            kCGPDFContextAuthor as String: statement.driverName ?? report.brand,
        ]
        UIGraphicsBeginPDFContextToData(bytes, bounds, info)
        Canvas(report: report, statement: statement, page: bounds).draw()
        UIGraphicsEndPDFContext()
        return bytes as Data
    }
}

private final class Canvas {
    let report: PeriodReport
    let statement: PeriodReportStatement
    let page: CGRect
    let margin: CGFloat = 36
    let footerReserve: CGFloat = 28
    var y: CGFloat = 0
    var pageOpen = false

    init(report: PeriodReport, statement: PeriodReportStatement, page: CGRect) {
        self.report = report
        self.statement = statement
        self.page = page
    }

    var contentWidth: CGFloat { page.width - margin * 2 }
    var contentBottom: CGFloat { page.height - footerReserve }
    var widths: [CGFloat] {
        let shares: [CGFloat] = [0.13, 0.16, 0.16, 0.11, 0.11, 0.10, 0.12, 0.11]
        return shares.map { contentWidth * $0 }
    }

    func draw() {
        beginPage()
        drawLetterhead()
        drawColumnHeader()
        if statement.rows.isEmpty {
            drawEmptyMessage()
        } else {
            for (index, row) in statement.rows.enumerated() {
                drawDataRow(row, stripe: index % 2 == 1, bold: false)
            }
            drawDataRow(statement.totalRow, stripe: false, bold: true, rule: true)
        }
        drawSummary()
        drawPageFooter()
    }

    func beginPage() {
        if pageOpen {
            drawPageFooter()
        }
        UIGraphicsBeginPDFPage()
        pageOpen = true
        UIColor.white.setFill()
        UIRectFill(page)
        y = margin
    }

    func drawLetterhead() {
        let leftWidth = contentWidth * 0.46
        let rightWidth = contentWidth - leftWidth
        let rightX = margin + leftWidth
        var leftY = y
        if let driver = statement.driverName, !driver.isEmpty {
            leftY += draw(driver, x: margin, y: y, width: leftWidth, font: Palette.nameFont, color: Palette.ink, align: .left)
        }
        var rightY = y
        rightY += draw(statement.title, x: rightX, y: rightY, width: rightWidth, font: Palette.titleFont, color: Palette.midnight, align: .right)
        rightY += 3
        rightY += draw(statement.periodLine, x: rightX, y: rightY, width: rightWidth, font: Palette.metaFont, color: Palette.ink, align: .right)
        rightY += 2
        rightY += draw(statement.generatedLine, x: rightX, y: rightY, width: rightWidth, font: Palette.metaFont, color: Palette.secondary, align: .right)
        y = max(leftY, rightY) + 8
        Palette.gold.setFill()
        UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 2))
        y += 14
    }

    func drawColumnHeader() {
        let height = rowHeight(statement.columns, font: Palette.headerFont) 
        ensure(height, repeatingHeader: false)
        Palette.headerFill.setFill()
        UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: height))
        drawCells(statement.columns, font: Palette.headerFont, color: Palette.ink, boldRow: true)
        y += height
    }

    func drawDataRow(_ cells: [String], stripe: Bool, bold: Bool, rule: Bool = false) {
        let font = bold ? Palette.totalFont : Palette.cellFont
        let height = rowHeight(cells, font: font)
        ensure(height, repeatingHeader: true)
        if rule {
            Palette.ink.setFill()
            UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 1))
        }
        if stripe {
            Palette.stripe.setFill()
            UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: height))
        }
        drawCells(cells, font: font, color: Palette.ink, boldRow: bold)
        y += height
    }

    func drawEmptyMessage() {
        let height = measure(statement.emptyMessage, width: contentWidth - 8, font: Palette.cellFont, align: .left) + 12
        ensure(height, repeatingHeader: true)
        _ = draw(statement.emptyMessage, x: margin + 4, y: y + 6, width: contentWidth - 8, font: Palette.cellFont, color: Palette.secondary, align: .left)
        y += height
    }

    func drawSummary() {
        let titleHeight = measure(statement.summaryTitle, width: contentWidth, font: Palette.sectionFont, align: .left) + 16
        ensure(titleHeight + 20, repeatingHeader: false)
        y += 16
        _ = draw(statement.summaryTitle, x: margin, y: y, width: contentWidth, font: Palette.sectionFont, color: Palette.midnight, align: .left)
        y += titleHeight - 8
        for line in statement.summary {
            let text = "\(line.label): \(line.value)"
            let height = measure(text, width: contentWidth, font: Palette.summaryFont, align: .left) + 4
            ensure(height, repeatingHeader: false)
            _ = draw(text, x: margin, y: y, width: contentWidth, font: Palette.summaryFont, color: Palette.ink, align: .left)
            y += height
        }
    }

    func ensure(_ height: CGFloat, repeatingHeader: Bool) {
        guard y + height > contentBottom else { return }
        beginPage()
        if repeatingHeader {
            drawColumnHeader()
        }
    }

    func drawCells(_ cells: [String], font: UIFont, color: UIColor, boldRow: Bool) {
        var x = margin
        let rowFont = font
        let height = rowHeight(cells, font: rowFont)
        for (index, cell) in cells.enumerated() {
            let width = index < widths.count ? widths[index] : 40
            let align: NSTextAlignment = index >= 5 ? .right : .left
            let inset: CGFloat = 3
            _ = draw(
                cell,
                x: x + inset,
                y: y + 4,
                width: max(width - inset * 2, 4),
                font: rowFont,
                color: color,
                align: align
            )
            x += width
            _ = boldRow
        }
        _ = height
    }

    func rowHeight(_ cells: [String], font: UIFont) -> CGFloat {
        var tallest: CGFloat = font.lineHeight
        for (index, cell) in cells.enumerated() {
            let width = index < widths.count ? widths[index] : 40
            let align: NSTextAlignment = index >= 5 ? .right : .left
            tallest = max(tallest, measure(cell, width: max(width - 6, 4), font: font, align: align))
        }
        return max(18, tallest + 8)
    }

    func drawPageFooter() {
        let baseline = page.height - 18
        _ = draw(
            "\(report.brand)  ·  \(statement.footer)",
            x: margin,
            y: baseline,
            width: contentWidth,
            font: Palette.footerFont,
            color: Palette.secondary,
            align: .left
        )
    }

    @discardableResult
    func draw(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        font: UIFont,
        color: UIColor,
        align: NSTextAlignment
    ) -> CGFloat {
        let height = measure(text, width: width, font: font, align: align)
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let rect = CGRect(x: x, y: y, width: max(width, 1), height: max(height, 1))
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        return height
    }

    func measure(_ text: String, width: CGFloat, font: UIFont, align: NSTextAlignment) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byWordWrapping
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: 2000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: style],
            context: nil
        )
        return ceil(bounds.height)
    }
}

private enum Palette {
    static let midnight = UIColor(red: 0x1E / 255, green: 0x21 / 255, blue: 0x50 / 255, alpha: 1)
    static let gold = UIColor(red: 0xC8 / 255, green: 0xA8 / 255, blue: 0x67 / 255, alpha: 1)
    static let ink = UIColor(red: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255, alpha: 1)
    static let secondary = UIColor(red: 0x66 / 255, green: 0x66 / 255, blue: 0x66 / 255, alpha: 1)
    static let headerFill = UIColor(red: 0xE6 / 255, green: 0xE6 / 255, blue: 0xE6 / 255, alpha: 1)
    static let stripe = UIColor(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255, alpha: 1)

    static let nameFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
    static let titleFont = UIFont.systemFont(ofSize: 16, weight: .bold)
    static let metaFont = UIFont.systemFont(ofSize: 9, weight: .regular)
    static let headerFont = UIFont.systemFont(ofSize: 8, weight: .bold)
    static let cellFont = UIFont.systemFont(ofSize: 8, weight: .regular)
    static let totalFont = UIFont.systemFont(ofSize: 8, weight: .bold)
    static let sectionFont = UIFont.systemFont(ofSize: 13, weight: .bold)
    static let summaryFont = UIFont.systemFont(ofSize: 11, weight: .regular)
    static let footerFont = UIFont.systemFont(ofSize: 8, weight: .regular)
}
