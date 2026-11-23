import Foundation
import ImageIO

enum ImageLocationStripError: Error {
    case encodeFailed
}

/// Removes GPS from a photo before it is uploaded.
///
/// Bytes with no GPS IFD and no XMP GPS packet are returned unchanged, so a PDF or a test
/// marker is not re-encoded. When GPS is present, ImageIO writes a new file without the GPS
/// dictionary and any XMP packet that still carries GPS is removed. A failed encode fails the
/// upload instead of sending the original bytes.
enum ImageLocationStrip {
    static func strip(_ data: Data) throws -> Data {
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        let count = source.map { CGImageSourceGetCount($0) } ?? 0
        let hasIFD = source.map(containsGPSIFD) ?? false
        let hasXMP = containsXMPGPS(data)
        guard hasIFD || hasXMP else { return data }
        guard let source, count > 0, let type = CGImageSourceGetType(source) else {
            throw ImageLocationStripError.encodeFailed
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, count, nil) else {
            throw ImageLocationStripError.encodeFailed
        }
        for index in 0..<count {
            var properties = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]) ?? [:]
            properties.removeValue(forKey: kCGImagePropertyGPSDictionary)
            CGImageDestinationAddImageFromSource(destination, source, index, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination), output.length > 0 else {
            throw ImageLocationStripError.encodeFailed
        }
        let stripped = removingXMPGPS(output as Data)
        if containsXMPGPS(stripped) || containsGPSIFD(of: stripped) {
            throw ImageLocationStripError.encodeFailed
        }
        return stripped
    }

    private static func containsGPSIFD(_ source: CGImageSource) -> Bool {
        let count = CGImageSourceGetCount(source)
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            if properties?[kCGImagePropertyGPSDictionary] != nil { return true }
        }
        return false
    }

    private static func containsGPSIFD(of data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return containsGPSIFD(source)
    }

    private static func containsXMPGPS(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .isoLatin1) else { return false }
        let packet = text.contains("http://ns.adobe.com/xap/1.0/") || text.contains("<?xpacket")
        let gps = text.contains("GPSLatitude") || text.contains("GPSLongitude")
        return packet && gps
    }

    /// Drops JPEG APP1 segments whose payload is an XMP packet that still names GPS.
    private static func removingXMPGPS(_ data: Data) -> Data {
        guard data.count > 2, data[0] == 0xFF, data[1] == 0xD8 else { return data }
        var output = Data([0xFF, 0xD8])
        var index = 2
        let bytes = [UInt8](data)
        while index + 4 <= bytes.count, bytes[index] == 0xFF {
            let marker = bytes[index + 1]
            if marker == 0xDA || marker == 0xD9 {
                output.append(contentsOf: bytes[index...])
                return output
            }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard length >= 2, index + 2 + length <= bytes.count else { return data }
            let segment = Data(bytes[index..<(index + 2 + length)])
            let payload = segment.dropFirst(4)
            let isXMP = payload.starts(with: Data("http://ns.adobe.com/xap/1.0/\0".utf8))
            if !(marker == 0xE1 && isXMP && containsXMPGPS(segment)) {
                output.append(segment)
            }
            index += 2 + length
        }
        if index < bytes.count {
            output.append(contentsOf: bytes[index...])
        }
        return output
    }
}
