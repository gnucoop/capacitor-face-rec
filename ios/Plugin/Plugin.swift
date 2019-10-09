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

import Capacitor
import FirebaseCore
import FirebaseMLCommon
import FirebaseMLModelInterpreter
import FirebaseMLVision
import Foundation
import Photos
import UIKit

enum DocLinks: String {
    case CAPPluginMethodSelector = "plugins/ios/#defining-methods"
    case NSPhotoLibraryAddUsageDescription = "https://developer.apple.com/library/content/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html#//apple_ref/doc/uid/TP40009251-SW73"
    case NSPhotoLibraryUsageDescription = "https://developer.apple.com/library/content/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html#//apple_ref/doc/uid/TP40009251-SW17"
    case NSCameraUsageDescription = "https://developer.apple.com/library/content/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html#//apple_ref/doc/uid/TP40009251-SW24"
}

enum FaceRecInitStatus: Int {
    case Init = 0
    case LoadingModel = 1
    case DownloadingModel = 2
    case Success = 3
    case Error = 4
}

enum FaceRecPhotoSource: Int {
    case Camera = 0
    case Gallery = 1
}

struct FaceRecPhotoSettings {
    var source: FaceRecPhotoSource = FaceRecPhotoSource.Camera
}

struct FaceRecInitSettings {
    var modelUrl: String?
    var batchSize: Int = 1;
    var pixelSize: Int = 3;
    var inputSize: Int = 64;
    var inputAsRgb: Bool = true;
}

@objc(FaceRec)
public class FaceRec: CAPPlugin, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIPopoverPresentationControllerDelegate, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate {
    
    private static let MISSING_INIT_PERMISSIONS = "Missing init permissions"
    private static let INVALID_MODEL_URL_ERROR = "Invalid model URL"
    private static let INVALID_PHOTO_SOURCE = "Invalid model URL"
    private static let MODEL_DOWNLOAD_ERROR = "Unable to download model"
    private static let NO_CAMERA_ERROR = "Device doesn't have a camera available"
    private static let IMAGE_FILE_SAVE_ERROR = "Unable to create photo on disk"
    private static let IMAGE_PROCESS_NO_FILE_ERROR = "Unable to process image, file not found on disk"
    private static let UNABLE_TO_PROCESS_BITMAP = "Unable to process bitmap"
    private static let UNABLE_TO_PROCESS_IMAGE = "Unable to process image"
    private static let NO_IMAGE_PICKED = "No image picked"
    private static let OUT_OF_MEMORY = "Out of memory"
    private static let NO_IMAGE_FOUND = "No image found"
    private static let NO_CAMERA_IN_SIMULATOR = "Camera not available while running in Simulator"
    private static let NO_CAMERA_AVAILABLE = "Camera not available"
    private static let GALLERY_NOT_PERMITTED = "User denied access to photos"
    private static let NO_PHOTO_SELECTED = "User cancelled photos app"
    private static let IMAGE_RESIZE_ERROR = "Error resizing image"
    private static let UNABLE_TO_CONVERT_TO_JPEG = "Unable to convert image to jpeg"
    
    private static let BUFFER_SIZE = 4096;
    private static let CACHE_PREFERENCES_NAME = "facerPluginCachePrefs";
    private static let COLOR_MALE = hexStringToUIColor("#6bcef5");
    private static let COLOR_FEMALE = hexStringToUIColor("#f4989d");
    private static let COLOR_INDETERMINATE = hexStringToUIColor("#c4db66");
    
    private var imagePicker: UIImagePickerController?
    private var call: CAPPluginCall?
    private var photoSettings = FaceRecPhotoSettings()
    private var initSettings = FaceRecInitSettings()
    private var fileUrl: URL?
    private var filePath: URL?
    private var dateFormatter = DateFormatter()
    private var faceDetector: VisionFaceDetector?
    private var interpreter: ModelInterpreter?
    lazy var vision = Vision.vision()
    
    private static func hexStringToUIColor (_ hex: String) -> UIColor {
        var cString:String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        if (cString.hasPrefix("#")) {
            cString.remove(at: cString.startIndex)
        }
        
        if ((cString.count) != 6) {
            return UIColor.gray
        }
        
        var rgbValue:UInt32 = 0
        Scanner(string: cString).scanHexInt32(&rgbValue)
        
        return UIColor(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: CGFloat(1.0)
        )
    }
    
    override public func load() {
        super.load()
        dateFormatter.dateFormat = "EEEE, dd LLL yyyy HH:mm:ss zzz"
    }
    
    @objc func initFaceRecognition(_ call: CAPPluginCall) -> Void {
        self.call = call
        
        notifyInitStatus(FaceRecInitStatus.Init)
        
        self.initSettings = getInitSettings(call)
        
        guard let modelUrl = self.initSettings.modelUrl else {
            notifyInitError(FaceRec.INVALID_MODEL_URL_ERROR)
            call.error(FaceRec.INVALID_MODEL_URL_ERROR)
            return
        }
        guard let url: URL = URL(string: modelUrl) else {
            notifyInitError(FaceRec.INVALID_MODEL_URL_ERROR)
            call.error(FaceRec.INVALID_MODEL_URL_ERROR)
            return
        }
        if url.scheme != "http" && url.scheme != "https" {
            notifyInitError(FaceRec.INVALID_MODEL_URL_ERROR)
            call.error(FaceRec.INVALID_MODEL_URL_ERROR)
            return
        }
        
        downloadFile(call, url, "gender_age_model", filename: "model.tflite")
    }
    
    @objc func getPhoto(_ call: CAPPluginCall) -> Void {
        self.call = call
        self.photoSettings = getPhotoSettings(call)
        
        // Make sure they have all the necessary info.plist settings
        if let missingUsageDescription = checkUsageDescriptions() {
            bridge.modulePrint(self, missingUsageDescription)
            call.error(missingUsageDescription)
            bridge.alert("FaceRec Error", "Missing required usage description. See console for more information")
            return
        }
        
        imagePicker = UIImagePickerController()
        imagePicker!.delegate = self
        
        DispatchQueue.main.async {
            switch self.photoSettings.source {
            case FaceRecPhotoSource.Camera:
                self.showCamera(call)
            case FaceRecPhotoSource.Gallery:
                self.showGallery(call)
            default:
                self.call?.error(FaceRec.INVALID_PHOTO_SOURCE)
            }
        }
    }
    
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        self.call?.error(FaceRec.NO_PHOTO_SELECTED)
    }
    
    public func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        self.call?.error(FaceRec.NO_PHOTO_SELECTED)
    }
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        var image: UIImage?
        picker.dismiss(animated: true, completion: nil)
        
        if let editedImage = info[UIImagePickerControllerEditedImage] as? UIImage {
            // Use editedImage Here
            image = editedImage
        } else if let originalImage = info[UIImagePickerControllerOriginalImage] as? UIImage {
            // Use originalImage Here
            image = originalImage
        }
        
        if faceDetector == nil || image == nil {
            call?.error(FaceRec.NO_IMAGE_FOUND)
        }
        
        image = image!.fixedOrientation()
        
        let imageMetadata = VisionImageMetadata()
        imageMetadata.orientation = UIUtilities.visionImageOrientation(from: image!.imageOrientation)
        
        let visionImage = VisionImage(image: image!)
        visionImage.metadata = imageMetadata
        
        var resFaces = [[String: Any]]()
        
        let imageWidth = Int(image!.size.width)
        let imageHeight = Int(image!.size.height)
        
        let faceByteCount = initSettings.batchSize * initSettings.inputSize * initSettings.inputSize * initSettings.pixelSize
        
        faceDetector!.process(visionImage) { faces, error in
            guard error == nil else {
                self.call?.error(FaceRec.UNABLE_TO_PROCESS_IMAGE)
                return
            }
            
            let interpretersGroup = DispatchGroup()
            
            if faces != nil && !faces!.isEmpty {
                let options = ModelInputOutputOptions()
                try? options.setInputFormat(index: 0, type: .float32, dimensions: [
                    NSNumber(value: self.initSettings.batchSize),
                    NSNumber(value: self.initSettings.inputSize),
                    NSNumber(value: self.initSettings.inputSize),
                    NSNumber(value: self.initSettings.pixelSize)
                    ])
                try? options.setOutputFormat(index: 0, type: .float32, dimensions: [
                    NSNumber(value: self.initSettings.batchSize),
                    NSNumber(value: 2)
                    ])
                
                var faceNum = 0
                for face in faces! {
                    faceNum += 1
                    let rect = face.frame
                    let width = Int(rect.width)
                    let height = Int(rect.height)
                    let size = max(width, height)
                    let cropWidth = min(imageWidth, size)
                    let cropHeight = min(imageHeight, size)
                    let midCropWidth = Int(round(Float(cropWidth) / Float(2)))
                    let midCropHeight = Int(round(Float(cropHeight) / Float(2)))
                    let x = min(imageWidth - cropWidth, max(0, Int(rect.midX) - midCropWidth))
                    let y = min(imageHeight - cropHeight, max(0, Int(rect.midY) - midCropHeight))
                    
                    let faceCrop = UIImage(cgImage: image!.cgImage!.cropping(to: CGRect.init(x: x, y: y, width: cropWidth, height: cropHeight))!)
                    let faceData = faceCrop.scaledData(with: CGSize.init(width: self.initSettings.inputSize, height: self.initSettings.inputSize), byteCount: faceByteCount, inputAsRgb: self.initSettings.inputAsRgb)
                    let facePng = UIImagePNGRepresentation(faceCrop)!
                    let docDir = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    let faceUrl = docDir.appendingPathComponent("face" + String(faceNum) + ".png")
                    try! facePng.write(to: faceUrl)
                    
                    let inputs = ModelInputs()
                    try? inputs.addInput(faceData as Any)
                    
                    interpretersGroup.enter()
                    self.interpreter?.run(inputs: inputs, options: options) { (outputs, error) in
                        guard error == nil else {
                            print(error.debugDescription)
                            self.call?.error(FaceRec.UNABLE_TO_PROCESS_IMAGE)
                            interpretersGroup.leave()
                            return
                        }
                        
                        let output = try? outputs!.output(index: 0) as? [[NSNumber]]
                        let gender = output??[0]
                        let male = Float(truncating: gender?[0] ?? 0)
                        let female = Float(truncating: gender?[1] ?? 0)
                        let resFace = [
                            "x": x,
                            "y": y,
                            "width": width,
                            "height": height,
                            "gender": [
                                "male": male,
                                "female": female
                                ] as [String: Float]
                            ] as [String: Any]
                        resFaces.append(resFace)
                        interpretersGroup.leave()
                    }
                }
            }
            
            interpretersGroup.notify(queue: DispatchQueue.global()) {
                let lineWidth = CGFloat(max(Float(3), min(Float(imageWidth), Float(imageHeight)) * 0.01))
                UIGraphicsBeginImageContextWithOptions(image!.size, false, 1)
                let context = UIGraphicsGetCurrentContext()!
                image!.draw(at: .zero)
                resFaces.forEach { face in
                    context.setStrokeColor(self.getColor(
                        (face["gender"] as! [String: Float])["male"] ?? 0,
                        (face["gender"] as! [String: Float])["female"] ?? 0
                        ).cgColor)
                    context.stroke(CGRect(
                        x: face["x"] as! Int,
                        y: face["y"] as! Int,
                        width: face["width"] as! Int,
                        height: face["height"] as! Int
                    ), width: lineWidth)
                }
                let taggedImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                
                guard let originalJpeg = UIImageJPEGRepresentation(image!, CGFloat(0.8)) else {
                    self.call?.error(FaceRec.UNABLE_TO_CONVERT_TO_JPEG)
                    return
                }
                
                guard let taggedJpeg = UIImageJPEGRepresentation(taggedImage!, CGFloat(0.8)) else {
                    self.call?.error(FaceRec.UNABLE_TO_CONVERT_TO_JPEG)
                    return
                }
                
                let imageMetadata = info[UIImagePickerControllerMediaMetadata] as? [AnyHashable: Any]
                var result = [String: Any]()
                result["originalImage"] = self.jpegToJson(originalJpeg, imageMetadata)
                result["taggedImage"] = self.jpegToJson(taggedJpeg, imageMetadata)
                result["faces"] = resFaces
                
                self.call?.success(result)
            }
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if fileUrl == nil || filePath == nil {
            doDownloadError()
            return
        }
        let fileManager = FileManager.default
        let fileDir = URL(string: filePath!.absoluteString)!.deletingLastPathComponent()
        do {
            if !fileManager.fileExists(atPath: fileDir.path) {
                try fileManager.createDirectory(atPath: fileDir.path, withIntermediateDirectories: true, attributes: nil)
            }
            try fileManager.moveItem(at: location, to: filePath!)
            setLastUpdate(fileUrl!)
            loadModel()
        } catch {
            doDownloadError()
            return
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        notifyInitStatus(.DownloadingModel, data: ["progress": Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)])
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let response = response as! HTTPURLResponse
        
        let responseStatus = response.statusCode
        dataTask.cancel()
        
        if responseStatus == 200 {
            let currentDate = Date()
            let headers = response.allHeaderFields
            let expires = headerToTimestamp(headers["Expires"], currentDate)
            let lastModified = headerToTimestamp(headers["Last-Modified"], currentDate)
            let lastUpdateTime = getLastUpdate(response.url!)
            
            if (lastModified > lastUpdateTime || expires < lastUpdateTime) {
                doDownloadFile()
                return
            }
        }
        
        loadModel()
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        loadModel()
    }
    
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        loadModel()
    }
    
    private func jpegToJson(_ data: Data, _ metadata: [AnyHashable: Any]?) -> [String: Any] {
        return [
            "exif": makeExif(metadata) ?? [:],
            "base64Data": "data:image/jpeg;base64," + data.base64EncodedString()
            ] as [String: Any]
    }
    
    private func makeExif(_ exif: [AnyHashable:Any]?) -> [AnyHashable:Any]? {
        return exif?["{Exif}"] as? [AnyHashable:Any]
    }
    
    private func getColor(_ male: Float, _ female: Float) -> UIColor {
        if (male < 0.5) { return FaceRec.COLOR_MALE }
        if (female < 0.5) { return FaceRec.COLOR_FEMALE }
        return FaceRec.COLOR_INDETERMINATE
    }
    
    private func showCamera(_ call: CAPPluginCall) -> Void {
        if self.bridge.isSimulator() || !UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.camera) {
            self.bridge.modulePrint(self, FaceRec.NO_CAMERA_IN_SIMULATOR)
            self.bridge.alert("FaceRec Error", FaceRec.NO_CAMERA_IN_SIMULATOR)
            call.error(FaceRec.NO_CAMERA_IN_SIMULATOR)
            return
        }
        
        self.imagePicker!.sourceType = .camera
        if UIImagePickerController.isCameraDeviceAvailable(.rear) {
            self.imagePicker!.cameraDevice = .rear
        }
        else if UIImagePickerController.isCameraDeviceAvailable(.front) {
            self.imagePicker!.cameraDevice = .rear
        } else {
            call.error(FaceRec.NO_CAMERA_AVAILABLE)
            return
        }
        
        self.bridge.viewController.present(self.imagePicker!, animated: true, completion: nil)
    }
    
    private func showGallery(_ call: CAPPluginCall) -> Void {
        let photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus()
        if photoAuthorizationStatus == .restricted || photoAuthorizationStatus == .denied {
            call.error(FaceRec.GALLERY_NOT_PERMITTED)
            return
        }
        
        self.imagePicker!.modalPresentationStyle = .popover
        self.imagePicker!.popoverPresentationController?.delegate = self
        self.setCenteredPopover(self.imagePicker!)
        self.bridge.viewController.present(self.imagePicker!, animated: true, completion: nil)
    }
    
    private func doDownloadError() -> Void {
        doError(FaceRec.MODEL_DOWNLOAD_ERROR)
    }
    
    private func doError(_ error: String) -> Void {
        notifyInitError(error)
        call?.error(error)
    }
    
    private func headerToTimestamp(_ header: Any?, _ currentDate: Date) -> Int64 {
        var date: Date
        switch header {
        case let headerStr as String:
            date = dateFormatter.date(from: headerStr) ?? currentDate
        case let headerDate as Date:
            date = headerDate
        default:
            date = currentDate
        }
        return Int64(date.timeIntervalSince1970) * 1000
    }
    
    private func doDownloadFile() -> Void {
        if fileUrl == nil || filePath == nil {
            doDownloadError()
            return
        }
        let req = URLRequest(url: fileUrl!)
        let session = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: req)
        task.resume()
    }
    
    private func loadModel() -> Void {
        let fileManager = FileManager.default
        let filePath = getFilePath("gender_age_model", "model.tflite")
        guard filePath != nil && fileManager.fileExists(atPath: filePath!.path) else {
            doDownloadError()
            return
        }
        
        notifyInitStatus(.LoadingModel)
        
        let app = FirebaseApp.app()
        if app == nil {
            FirebaseApp.configure()
        }
        
        let visionOptions = VisionFaceDetectorOptions()
        visionOptions.performanceMode = .fast
        visionOptions.landmarkMode = .none
        visionOptions.classificationMode = .none
        visionOptions.isTrackingEnabled = false
        
        faceDetector = vision.faceDetector(options: visionOptions)
        
        let normFilePath = filePath!.absoluteString.replacingOccurrences(of: "file://", with: "")
        let modelSource = LocalModel(name: "gender_age_model", path: normFilePath)
        guard ModelManager.modelManager().register(modelSource) else {
            doDownloadError()
            return
        }
        
        let modelOptions = ModelOptions(remoteModelName: nil, localModelName: "gender_age_model")
        interpreter = ModelInterpreter.modelInterpreter(options: modelOptions)
        
        notifyInitStatus(FaceRecInitStatus.Success)
        call?.success(["status": FaceRecInitStatus.Success.rawValue])
    }
    
    private func getLastUpdate(_ url: URL) -> Int64 {
        return UserDefaults.standard.object(forKey: "last-update-" + url.absoluteString) as! Int64? ?? 0
    }
    
    private func setLastUpdate(_ url: URL) -> Void {
        let currentTime = Int64(Date().timeIntervalSince1970) * 1000
        UserDefaults.standard.set(currentTime, forKey: "last-update-" + url.absoluteString)
        UserDefaults.standard.synchronize()
    }
    
    private func downloadFile(_ call: CAPPluginCall, _ url: URL, _ dest: String, filename: String?) -> Void {
        let filename: String = filename ?? url.lastPathComponent
        self.fileUrl = url
        
        guard let filePath = getFilePath(dest, filename) else {
            notifyInitError(FaceRec.MODEL_DOWNLOAD_ERROR)
            call.error(FaceRec.MODEL_DOWNLOAD_ERROR)
            return
        }
        
        self.filePath = filePath
        
        let req = URLRequest(url: url)
        let session = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: req)
        task.resume()
    }
    
    private func getFilePath(_ dest: String, _ filename: String) -> URL? {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard var url = urls.first else {
            return nil
        }
        url.appendPathComponent(dest)
        url.appendPathComponent(filename)
        return url
    }
    
    private func getInitSettings(_ call: CAPPluginCall) -> FaceRecInitSettings {
        var settings = FaceRecInitSettings()
        settings.modelUrl = call.get("modelUrl", String.self)
        if call.hasOption("batchSize"), let optBatchSize = call.getInt("batchSize") {
            settings.batchSize = optBatchSize
        }
        if call.hasOption("inputSize"), let optInputSize = call.getInt("inputSize") {
            settings.inputSize = optInputSize
        }
        if call.hasOption("pixelSize"), let optPixelSize = call.getInt("pixelSize") {
            settings.pixelSize = optPixelSize
        }
        if call.hasOption("inputAsRgb"), let optInputAsRgb = call.getBool("inputAsRgb") {
            settings.inputAsRgb = optInputAsRgb
        }
        return settings
    }
    
    private func getPhotoSettings(_ call: CAPPluginCall) -> FaceRecPhotoSettings {
        var settings = FaceRecPhotoSettings()
        settings.source = FaceRecPhotoSource(rawValue: call.getInt("source") ?? FaceRecPhotoSource.Camera.rawValue) ?? FaceRecPhotoSource.Camera
        return settings
    }
    
    private func notifyInitStatus(_ status: FaceRecInitStatus, data: [String: Any] = [:]) {
        var data = data
        data["status"] = status.rawValue
        notifyListeners("facerInitStatusChanged", data: data)
    }
    
    private func notifyInitError(_ error: String) {
        notifyListeners("facerInitStatusChanged", data: ["error": error])
    }
    
    /**
     * Make sure the developer provided proper usage descriptions
     * per apple's terms.
     */
    private func checkUsageDescriptions() -> String? {
        if let dict = Bundle.main.infoDictionary {
            let hasPhotoLibraryAddUsage = dict["NSPhotoLibraryAddUsageDescription"] != nil
            if !hasPhotoLibraryAddUsage {
                let docLink = DocLinks.NSPhotoLibraryAddUsageDescription
                return "You are missing NSPhotoLibraryAddUsageDescription in your Info.plist file." +
                " Camera will not function without it. Learn more: \(docLink.rawValue)"
            }
            let hasPhotoLibraryUsage = dict["NSPhotoLibraryUsageDescription"] != nil
            if !hasPhotoLibraryUsage {
                let docLink = DocLinks.NSPhotoLibraryUsageDescription
                return "You are missing NSPhotoLibraryUsageDescription in your Info.plist file." +
                " Camera will not function without it. Learn more: \(docLink.rawValue)"
            }
            let hasCameraUsage = dict["NSCameraUsageDescription"] != nil
            if !hasCameraUsage {
                let docLink = DocLinks.NSCameraUsageDescription
                return "You are missing NSCameraUsageDescription in your Info.plist file." +
                " Camera will not function without it. Learn more: \(docLink.rawValue)"
            }
        }
        
        return nil
    }
}
