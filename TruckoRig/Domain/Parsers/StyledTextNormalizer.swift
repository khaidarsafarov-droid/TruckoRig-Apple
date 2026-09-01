import Foundation

/// Folds Unicode "mathematical" letterforms back to ASCII.
///
/// Relay reposts frequently arrive as 𝗧𝗿𝗶𝗽 𝗜𝗗 rather than `Trip ID`, which would otherwise defeat
/// every keyword in the parser.
public enum StyledTextNormalizer {

    public static func normalize(_ input: String) -> String {
        guard input.unicodeScalars.contains(where: { $0.value > 0xFFFF }) else { return input }
        var output = String.UnicodeScalarView()
        output.reserveCapacity(input.unicodeScalars.count)
        for scalar in input.unicodeScalars {
            output.append(deStyle(scalar))
        }
        return String(output)
    }

    private static let letterBlocks: [(range: ClosedRange<UInt32>, base: UInt32)] = [
        (0x1D400...0x1D419, 0x41), (0x1D41A...0x1D433, 0x61),  // bold
        (0x1D434...0x1D44D, 0x41), (0x1D44E...0x1D467, 0x61),  // italic
        (0x1D468...0x1D481, 0x41), (0x1D482...0x1D49B, 0x61),  // bold italic
        (0x1D5D4...0x1D5ED, 0x41), (0x1D5EE...0x1D607, 0x61),  // sans bold
        (0x1D608...0x1D621, 0x41), (0x1D622...0x1D63B, 0x61),  // sans italic
        (0x1D63C...0x1D655, 0x41), (0x1D656...0x1D66F, 0x61),  // sans bold italic
        (0x1D7CE...0x1D7D7, 0x30), (0x1D7E2...0x1D7EB, 0x30),  // bold / sans digits
    ]

    private static func deStyle(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        let code = scalar.value
        guard code > 0xFFFF else { return scalar }
        for block in letterBlocks where block.range.contains(code) {
            let plain = block.base + (code - block.range.lowerBound)
            return Unicode.Scalar(plain) ?? scalar
        }
        return scalar
    }
}
