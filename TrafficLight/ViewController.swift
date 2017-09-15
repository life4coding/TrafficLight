//
//  ViewController.swift
//  TrafficLight
//
//  Created by kyx on 2017/6/16.
//  Copyright © 2017年 DIFF. All rights reserved.
//

import UIKit
import CoreGraphics
import AVFoundation
import Vision

class ViewController: UIViewController,AVCaptureVideoDataOutputSampleBufferDelegate {
    
    
    @IBOutlet weak var stopPic: UIImageView!
     @IBOutlet weak var go: UIImageView!
     @IBOutlet weak var nothing: UIImageView!
    @IBOutlet weak var predictLabel: UILabel!
    
    let TrafficLightModel = TFM()

    var requests = [VNRequest]()
    var captureSession = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupVision()
        setUpCaptureSession()
        // Do any additional setup after loading the view, typically from a nib.
    }
    

    func setUpCaptureSession(){
        
        captureSession = AVCaptureSession.init()
        captureSession.sessionPreset = .inputPriority
        
        
        guard let catptureDevice = configureDevice() else{return}
        
        guard let input = try? AVCaptureDeviceInput.init(device: catptureDevice) else {fatalError("cant init captureDeviceInput")}
        
        captureSession.addInput(input)
        
        let output = AVCaptureVideoDataOutput.init()
        
        let queue = DispatchQueue.init(label: "com.kiwi.videocapturequeue")
        output.setSampleBufferDelegate(self, queue: queue)
        output.videoSettings =  [kCVPixelBufferPixelFormatTypeKey as AnyHashable as! String: NSNumber(value: kCVPixelFormatType_32BGRA)]
        output.alwaysDiscardsLateVideoFrames = true
        
        guard captureSession.canAddOutput(output) else {
            fatalError()
        }
        
        captureSession.addOutput(output)
        startCapturingWithSession(captureSession: captureSession)
    }
    
    func configureDevice()->AVCaptureDevice?{
        
        guard let device = AVCaptureDevice.default(for: .video) else {return nil}

        var customFormats = [AVCaptureDevice.Format]()
        
        let customFPS = Float64(3)
        for format in device.formats{
            
            for range in format.videoSupportedFrameRateRanges where range.minFrameRate <= customFPS && customFPS <= range.maxFrameRate {
                customFormats.append(format)
            }
        }
        
        let customSize = CGSize.init(width: 227, height: 227)
        
        var sizeFormat : AVCaptureDevice.Format?
        for format in customFormats{
            
            let desc = format.formatDescription
            let dimesions = CMVideoFormatDescriptionGetDimensions(desc)
            
            if dimesions.width >= Int32(customSize.width) && dimesions.height >= Int32(customSize.height){
                
                sizeFormat = format
            }
        }
        
        do { try device.lockForConfiguration() }catch{fatalError(" error when request configration") }
        
        device.activeFormat = sizeFormat!
        
        device.activeVideoMaxFrameDuration = CMTimeMake(1, Int32(customFPS))
        device.activeVideoMinFrameDuration = CMTimeMake(1, Int32(customFPS))
        
        device.focusMode = .continuousAutoFocus
        
        device.unlockForConfiguration()
        
        return device
        
        }
    
    func startCapturingWithSession(captureSession cap: AVCaptureSession){
        
        if previewLayer == nil {
            previewLayer = AVCaptureVideoPreviewLayer.init(session: cap)
            previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
            previewLayer?.frame.origin = self.view.frame.origin
            previewLayer?.frame.size = self.view.frame.size
            
            self.view.layer.insertSublayer(previewLayer!, at:1)
        }
        
        cap.startRunning()
        
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
       handleImageBufferWithCoreML(imageBuffer: sampleBuffer)
        
        //handleImageBufferWithVision(imageBuffer: sampleBuffer)
        
    }
    
    func setupVision() {
        guard let visionModel = try? VNCoreMLModel(for: TrafficLightModel.model) else {
            fatalError("error when load model")
        }
        let classificationRequest = VNCoreMLRequest(model: visionModel) { (request: VNRequest, error: Error?) in
            guard let observations = request.results else {
                print(" error :\(error!)")
                return
            }
            
            let classifications = observations[0...2]
                .flatMap({ $0 as? VNClassificationObservation })
                .filter({ $0.confidence > 0 })
                .map({ "\($0.identifier) \($0.confidence)" })
            DispatchQueue.main.async {
                self.predictLabel.text = classifications.joined(separator: "\n")
            }
        }
        classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop
        
        self.requests = [classificationRequest]
    }
    
    
    func handleImageBufferWithCoreML(imageBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(imageBuffer) else {
            return
        }
        do {
            
            let prediction = try self.TrafficLightModel.prediction(data:  resize(pixelBuffer: pixelBuffer)!)
            DispatchQueue.main.async {
               
               self.predictLabel.lineBreakMode = NSLineBreakMode.byWordWrapping
                self.predictLabel.numberOfLines = 0
                self.predictLabel.text = " none \(String(describing: prediction.prob["none"]!)) \n green \(String(describing: prediction.prob["green"]!)) \n red \(String(describing: prediction.prob["red"]!))"
            }
        }
        catch let error as NSError {
            fatalError("Unexpected error ocurred: \(error.localizedDescription).")
        }
    }
    
    func handleImageBufferWithVision(imageBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(imageBuffer) else {
            return
        }
        
        var requestOptions:[VNImageOption : Any] = [:]
        
        if let cameraIntrinsicData = CMGetAttachment(imageBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics:cameraIntrinsicData]
        }
        
        let imageRH = VNImageRequestHandler.init(cvPixelBuffer: pixelBuffer, options: requestOptions)
        
        do {
            try imageRH.perform(self.requests)
        } catch {
            print(error)
        }
    }
    
    func resize(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let imageSide = 227
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer, options: nil)
        let transform = CGAffineTransform(scaleX: CGFloat(imageSide) / CGFloat(CVPixelBufferGetWidth(pixelBuffer)), y: CGFloat(imageSide) / CGFloat(CVPixelBufferGetHeight(pixelBuffer)))
        ciImage = ciImage.transformed(by: transform).cropped(to: CGRect(x: 0, y: 0, width: imageSide, height: imageSide))
        let ciContext = CIContext()
        
        var resBuf: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, imageSide, imageSide, CVPixelBufferGetPixelFormatType(pixelBuffer), nil, &resBuf)
        ciContext.render(ciImage, to: resBuf!)
        return resBuf
    }
    
}
