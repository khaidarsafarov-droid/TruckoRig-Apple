import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import TruckoRig

final class ImageLocationStripTests: XCTestCase {
    func testBytesWithoutGPSAreReturnedUnchanged() throws {
        let marker = Data("%PDF-1.4 no gps".utf8)
        XCTAssertEqual(try ImageLocationStrip.strip(marker), marker)
        let jpeg = try makeJPEG(gps: false)
        XCTAssertEqual(try ImageLocationStrip.strip(jpeg), jpeg)
    }

    func testOrientationSurvivesGPSRemoval() throws {
        var jpeg = try makeJPEG(gps: true, orientation: 6)
        jpeg = injectXMP(jpeg)
        let stripped = try ImageLocationStrip.strip(jpeg)
        XCTAssertFalse(hasGPSIFD(stripped))
        XCTAssertEqual(orientation(of: stripped), 6)
        XCTAssertFalse(String(decoding: stripped, as: UTF8.self).contains("GPSLatitude"))
    }

    func testGPSIFDAndXMPPacketAreRemoved() throws {
        var jpeg = try makeJPEG(gps: true)
        jpeg = injectXMP(jpeg)
        let text = String(decoding: jpeg, as: UTF8.self)
        XCTAssertTrue(text.contains("GPSLatitude") || hasGPSIFD(jpeg))
        let stripped = try ImageLocationStrip.strip(jpeg)
        XCTAssertFalse(hasGPSIFD(stripped))
        XCTAssertFalse(String(decoding: stripped, as: UTF8.self).contains("GPSLatitude"))
        XCTAssertNotEqual(stripped, jpeg)
    }

    private func hasGPSIFD(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        let count = CGImageSourceGetCount(source)
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            if properties?[kCGImagePropertyGPSDictionary] != nil { return true }
        }
        return false
    }

    private func orientation(of data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        if let number = properties[kCGImagePropertyOrientation] as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func makeJPEG(gps: Bool, orientation: Int? = nil) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ), let image = context.makeImage() else {
            throw ImageLocationStripError.encodeFailed
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageLocationStripError.encodeFailed
        }
        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        if gps {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 35.123,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 78.456,
                kCGImagePropertyGPSLongitudeRef: "W",
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageLocationStripError.encodeFailed }
        return output as Data
    }

    private func injectXMP(_ jpeg: Data) -> Data {
        let packet = """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>\
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\
        <rdf:Description xmlns:exif="http://ns.adobe.com/exif/1.0/" exif:GPSLatitude="35,7.38N"/>\
        </rdf:RDF></x:xmpmeta><?xpacket end="w"?>
        """
        var payload = Data("http://ns.adobe.com/xap/1.0/\0".utf8)
        payload.append(Data(packet.utf8))
        var segment = Data([0xFF, 0xE1])
        let length = UInt16(payload.count + 2)
        segment.append(UInt8(length >> 8))
        segment.append(UInt8(length & 0xFF))
        segment.append(payload)
        var result = Data(jpeg.prefix(2))
        result.append(segment)
        result.append(jpeg.dropFirst(2))
        return result
    }
}
