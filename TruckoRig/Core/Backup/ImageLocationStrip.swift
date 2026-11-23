import Foundation
import ImageIO

/// Removes GPS dictionaries from a photo before it is uploaded.
///
/// ImageIO copies the image and drops `kCGImagePropertyGPSDictionary`. Bytes that are not an
/// image (a PDF, or a test marker) are returned unchanged. The local photo on the phone is not
/// modified.
enum ImageLocationStrip {
    static func strip(_ data: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source)
        else { return data }
        let count = CGImageSourceGetCount(source)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, count, nil) else {
            return data
        }
        for index in 0..<count {
            var properties = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]) ?? [:]
            properties.removeValue(forKey: kCGImagePropertyGPSDictionary)
            CGImageDestinationAddImageFromSource(destination, source, index, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination), output.length > 0 else { return data }
        return output as Data
    }
}
