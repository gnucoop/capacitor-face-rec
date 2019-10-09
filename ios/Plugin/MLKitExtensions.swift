/**
 * Copyright (C) 2019 Gnucoop soc. coop.
 *
 * This file is part of c2s.
 *
 * c2s is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * c2s is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with c2s.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import CoreGraphics
import Foundation
import UIKit

// MARK: - UIImage
extension UIImage {
    
    /// Creates and returns a new image scaled to the given size. The image preserves its original PNG
    /// or JPEG bitmap info.
    ///
    /// - Parameter size: The size to scale the image to.
    /// - Returns: The scaled image or `nil` if image could not be resized.
    public func scaledImage(with size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // Convert the scaled image to PNG or JPEG data to preserve the bitmap info.
        return scaledImage?.data.map { UIImage(data: $0) } ?? nil
    }
    
    /// Returns the data representation of the image after scaling to the given `size` and removing
    /// the alpha component.
    ///
    /// - Parameters
    ///   - size: Size to scale the image to (i.e. image size used while training the model).
    ///   - byteCount: The expected byte count for the scaled image data calculated using the values
    ///       that the model was trained on: `imageWidth * imageHeight * componentsCount * batchSize`.
    ///   - isQuantized: Whether the model is quantized (i.e. fixed point values rather than floating
    ///       point values).
    /// - Returns: The scaled image as data or `nil` if the image could not be scaled.
    public func scaledData(with size: CGSize, byteCount: Int, floatNet: Bool = true, inputAsRgb: Bool = true, inputMean: [Float32] = [127.5, 127.5, 127.5], inputStd: [Float32?] = [127.5, 127.5, 127.5]) -> Data? {
        guard let cgImage = self.cgImage, cgImage.width > 0, cgImage.height > 0 else { return nil }
        guard let imageData = imageData(from: cgImage, with: size) else { return nil }
        var inputData = Data()
        let intWidth = Int(size.width)
        let intHeight = Int(size.height)
        for row in 0 ..< intWidth {
            for col in 0 ..< intHeight {
                let offset = 4 * (row * intWidth + col)
                let firstInt = imageData[inputAsRgb ? offset : offset+2] as UInt8
                let secondInt = imageData[offset+1] as UInt8
                let thirdInt = imageData[inputAsRgb ? offset+2 : offset] as UInt8
                var first: Any
                var second: Any
                var third: Any
                if (floatNet) {
                    first = (Float32(firstInt) - inputMean[0]) / Float32(inputStd[0] != nil ? inputStd[0]! : 1)
                    second = (Float32(secondInt) - inputMean[1]) / Float32(inputStd[1] != nil ? inputStd[1]! : 1)
                    third = (Float32(thirdInt) - inputMean[2]) / Float32(inputStd[2] != nil ? inputStd[2]! : 1)
                } else {
                    first = firstInt
                    second = secondInt
                    third = thirdInt
                }
                let elementSize = MemoryLayout.size(ofValue: first)
                var bytes = [UInt8](repeating: 0, count: elementSize)
                memcpy(&bytes, &first, elementSize)
                inputData.append(&bytes, count: elementSize)
                memcpy(&bytes, &second, elementSize)
                inputData.append(&bytes, count: elementSize)
                memcpy(&bytes, &third, elementSize)
                inputData.append(&bytes, count: elementSize)
            }
        }
        return inputData
    }
    
    // MARK: - Private
    /// The PNG or JPEG data representation of the image or `nil` if the conversion failed.
    private var data: Data? {
        #if swift(>=4.2)
        return self.pngData() ?? self.jpegData(compressionQuality: Constant.jpegCompressionQuality)
        #else
        return UIImagePNGRepresentation(self) ??
            UIImageJPEGRepresentation(self, Constant.jpegCompressionQuality)
        #endif  // swift(>=4.2)
    }
    
    /// Returns the image data for the given CGImage based on the given `size`.
    private func imageData(from cgImage: CGImage, with size: CGSize) -> Data? {
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let width = Int(size.width)
        let height = Int(size.height)
        let scaledBytesPerRow = (cgImage.bytesPerRow / cgImage.width) * width
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: scaledBytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue)
            else {
                return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()?.dataProvider?.data as Data?
    }
}

// MARK: - Data
extension Data {
    /// Creates a new buffer by copying the buffer pointer of the given array.
    ///
    /// - Warning: The given array's element type `T` must be trivial in that it can be copied bit
    ///     for bit with no indirection or reference-counting operations; otherwise, reinterpreting
    ///     data from the resulting buffer has undefined behavior.
    /// - Parameter array: An array with elements of type `T`.
    init<T>(copyingBufferOf array: [T]) {
        self = array.withUnsafeBufferPointer(Data.init)
    }
}

// MARK: - Constants
private enum Constant {
    static let jpegCompressionQuality: CGFloat = 0.8
    static let alphaComponent = (baseOffset: 4, moduloRemainder: 3)
    static let maxRGBValue: Float32 = 255.0
}
