import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Zoji

final class AvatarCropTests: XCTestCase {
    @MainActor
    func testOffCenterCropExportsOnlyTheSelectedRegion() throws {
        let image = stripedImage(size: CGSize(width: 600, height: 200))
        let data = try XCTUnwrap(AvatarImageProcessor.crop(image, to: CGRect(x: 400, y: 0, width: 200, height: 200)))
        let result = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(result.size, CGSize(width: 200, height: 200))
        assertBlue(result)
    }

    @MainActor
    func testExportLimitsSizeAndDoesNotUpscaleSmallCrops() throws {
        let image = stripedImage(size: CGSize(width: 2_400, height: 1_200))
        for (side, expected) in [(CGFloat(1_200), CGFloat(1_024)), (120, 120)] {
            let data = try XCTUnwrap(AvatarImageProcessor.crop(image, to: CGRect(x: 0, y: 0, width: side, height: side)))
            XCTAssertEqual(UIImage(data: data)?.size, CGSize(width: expected, height: expected))
        }
        XCTAssertNil(AvatarImageProcessor.crop(image, to: .zero))
        XCTAssertNil(AvatarImageProcessor.prepare(Data([0, 1, 2])))
    }

    @MainActor
    func testPreparationNormalizesEXIFRotationAndMirroring() throws {
        let image = stripedImage(size: CGSize(width: 600, height: 200))
        for orientation in [2, 6] {
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [
                kCGImagePropertyOrientation: orientation
            ] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let result = try XCTUnwrap(AvatarImageProcessor.prepare(data as Data))
            XCTAssertEqual(result.imageOrientation, .up)
            XCTAssertEqual(result.size, orientation == 2 ? image.size : CGSize(width: 200, height: 600))
            // Mirroring moves the blue stripe from the right edge to the left.
            if orientation == 2 {
                let cropped = try XCTUnwrap(AvatarImageProcessor.crop(result, to: CGRect(x: 0, y: 0, width: 200, height: 200)))
                assertBlue(try XCTUnwrap(UIImage(data: cropped)))
            }
        }
    }

    @MainActor
    func testPreparationBoundsLargeImages() throws {
        let image = stripedImage(size: CGSize(width: 5_000, height: 100))
        let result = try XCTUnwrap(AvatarImageProcessor.prepare(try XCTUnwrap(image.jpegData(compressionQuality: 0.9))))
        XCTAssertEqual(result.size.width, 4_096)
        XCTAssertGreaterThan(result.size.height, 0)
    }

    @MainActor
    func testPanAndZoomExportTheVisibleRegion() throws {
        let cropView = makeCropView(imageSize: CGSize(width: 600, height: 200))
        XCTAssertEqual(cropView.minimumZoomScale, 1.5, accuracy: 0.001)
        XCTAssertEqual(cropView.contentOffset.x, 300, accuracy: 0.001)
        cropView.contentOffset = CGPoint(x: 600, y: 0)
        cropView.setRelativeZoom(2)
        let data = try XCTUnwrap(cropView.croppedData())
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(image.size, CGSize(width: 100, height: 100))
        assertBlue(image)
    }

    @MainActor
    func testZoomOutClampsEdgesForPortraitAndLandscapeImages() {
        for size in [CGSize(width: 600, height: 200), CGSize(width: 200, height: 600)] {
            let cropView = makeCropView(imageSize: size)
            cropView.setRelativeZoom(5)
            cropView.contentOffset = CGPoint(x: cropView.contentSize.width - 300, y: cropView.contentSize.height - 300)
            cropView.setRelativeZoom(1)
            XCTAssertGreaterThanOrEqual(cropView.contentOffset.x, 0)
            XCTAssertGreaterThanOrEqual(cropView.contentOffset.y, 0)
            XCTAssertLessThanOrEqual(cropView.contentOffset.x + 300, cropView.contentSize.width + 0.01)
            XCTAssertLessThanOrEqual(cropView.contentOffset.y + 300, cropView.contentSize.height + 0.01)
            cropView.resetCrop()
            XCTAssertEqual(cropView.zoomScale, cropView.minimumZoomScale, accuracy: 0.001)
            XCTAssertEqual(cropView.contentOffset.x, (cropView.contentSize.width - 300) / 2, accuracy: 0.001)
            XCTAssertEqual(cropView.contentOffset.y, (cropView.contentSize.height - 300) / 2, accuracy: 0.001)
        }
    }

    @MainActor
    func testViewportResizePreservesComposition() throws {
        let cropView = makeCropView(imageSize: CGSize(width: 600, height: 200))
        cropView.contentOffset.x = 600
        cropView.setRelativeZoom(3)
        let before = try XCTUnwrap(cropView.croppedData())
        cropView.frame.size = CGSize(width: 240, height: 240)
        cropView.layoutIfNeeded()
        XCTAssertEqual(cropView.zoomScale / cropView.minimumZoomScale, 3, accuracy: 0.001)
        XCTAssertEqual(cropView.croppedData(), before)
    }

    @MainActor
    private func makeCropView(imageSize: CGSize) -> AvatarCropScrollView {
        let view = AvatarCropScrollView(image: stripedImage(size: imageSize))
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        view.layoutIfNeeded()
        return view
    }

    @MainActor
    private func stripedImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            for (index, color) in [UIColor.red, .green, .blue].enumerated() {
                color.setFill()
                UIRectFill(CGRect(x: CGFloat(index) * size.width / 3, y: 0, width: size.width / 3, height: size.height))
            }
        }
    }

    private func assertBlue(_ image: UIImage, file: StaticString = #filePath, line: UInt = #line) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertLessThan(pixel[0], 20, file: file, line: line)
        XCTAssertLessThan(pixel[1], 20, file: file, line: line)
        XCTAssertGreaterThan(pixel[2], 230, file: file, line: line)
    }
}
