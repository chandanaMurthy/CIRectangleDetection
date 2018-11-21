//
//  ChildViewController.swift
//  CIdetectLib
//
//  Created by Chandana on 11/20/18.
//  Copyright © 2018 Chandana. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

class ChildViewController: UIViewController {
    var isAutoCaptureEnabled = false
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let videoCaptureOutput = AVCaptureVideoDataOutput()
    private let photoCaptureOutput = AVCapturePhotoOutput()
    
    private let sampleBufferQueue = DispatchQueue.global(qos: .userInteractive)
    private let ciContext = CIContext()
    private var path: UIBezierPath?
    
    private var frameCount = 0
    private var rectangleDetectionFrequency = 5
    
    private var autoCaptureFrameCount = 0
    private var autoCaptureContainerRect: CGRect!
    private let autoCaptureFrameCountThreshold = 25
    
    lazy private var captureSession: AVCaptureSession = {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        return session
    }()
    
    lazy private var rectDetector: CIDetector = {
        return CIDetector(ofType: CIDetectorTypeRectangle,
                          context: self.ciContext,
                          options: [CIDetectorAccuracy : CIDetectorAccuracyHigh])!
    }()
    
    lazy private var quadLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.white.cgColor
        layer.lineWidth = 2.0
        layer.opacity = 0.5
        layer.borderWidth = 2
        layer.borderColor = UIColor.blue.cgColor
        return layer
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.layer.addSublayer(quadLayer)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            setupCaptureSession()
        } else {
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { (authorized) in
                DispatchQueue.main.async {
                    if authorized {
                        self.setupCaptureSession()
                    }
                }
            })
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.bounds = view.frame
    }
    
    public func capturePhoto() {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isAutoStillImageStabilizationEnabled = true
        photoSettings.isHighResolutionPhotoEnabled = true
        photoSettings.flashMode = .off
        
        photoCaptureOutput.capturePhoto(with: photoSettings, delegate: self)
    }
    
    private func findCamera() -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInDualCamera,
            .builtInTelephotoCamera,
            .builtInWideAngleCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .back)
        return discovery.devices.first
    }
    
    private func setupCaptureSession() {
        guard captureSession.inputs.isEmpty else { return }
        guard let camera = findCamera() else {
            print("No camera found")
            return
        }
        
        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            captureSession.addInput(cameraInput)
            
            let preview = AVCaptureVideoPreviewLayer(session: captureSession)
            preview.frame = view.bounds
            preview.backgroundColor = UIColor.black.cgColor
            preview.videoGravity = .resizeAspect
            view.layer.insertSublayer(preview, below: quadLayer)
            self.previewLayer = preview
            
            photoCaptureOutput.isHighResolutionCaptureEnabled = true
            videoCaptureOutput.alwaysDiscardsLateVideoFrames = true
            videoCaptureOutput.setSampleBufferDelegate(self, queue: sampleBufferQueue)
            
            captureSession.addOutput(videoCaptureOutput)
            captureSession.addOutput(photoCaptureOutput)
            
            captureSession.startRunning()
            
        } catch let error {
            print("Error creating capture session: \(error)")
            return
        }
    }
    
    private func autoCaptureAssist(rect: CGRect) {
        if self.autoCaptureContainerRect == nil {
            makeContainerRect(with: rect)
        }
        
        if autoCaptureFrameCount >= autoCaptureFrameCountThreshold {
            self.autoCaptureFrameCount = 0
            let photoSettings = AVCapturePhotoSettings()
            photoSettings.isAutoStillImageStabilizationEnabled = true
            photoSettings.isHighResolutionPhotoEnabled = true
            photoSettings.flashMode = .off
            photoCaptureOutput.capturePhoto(with: photoSettings, delegate: self)
        } else {
            if autoCaptureContainerRect.contains(rect) {
                self.autoCaptureFrameCount += 1
            } else {
                makeContainerRect(with: rect)
                self.autoCaptureFrameCount = 0
            }
        }
    }
    
    private func makeContainerRect(with rect: CGRect) {
        let x = rect.origin.x - 50
        let y = rect.origin.y - 50
        let width = rect.width + 100
        let height = rect.height + 100
        let containerRect = CGRect(x: x, y: y, width: width, height: height)
        
        self.autoCaptureContainerRect = containerRect
    }
}

extension ChildViewController : AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        frameCount += 1
        guard frameCount % rectangleDetectionFrequency == 0 else {
            return
        }
        if frameCount >= 99 {
            frameCount = 0
        }
        
        let image = CIImage(cvImageBuffer: imageBuffer)
        guard let rectFeature = rectDetector.features(in: image).first as? CIRectangleFeature else {
            DispatchQueue.main.async {
                self.quadLayer.path = nil
            }
            return
        }
        let imageWidth = image.extent.height
        let imageHeight = image.extent.width
        
        DispatchQueue.main.sync {
            let imageScale = min(view.frame.size.width / imageWidth,
                                 view.frame.size.height / imageHeight)
            
            let newTopLeft = CGPoint(x: rectFeature.topLeft.y * imageScale, y: rectFeature.topLeft.x * imageScale)
            let newTopRight = CGPoint(x: rectFeature.topRight.y * imageScale, y: rectFeature.topRight.x * imageScale)
            let newBottomRight = CGPoint(x: rectFeature.bottomRight.y * imageScale, y: rectFeature.bottomRight.x * imageScale)
            let newBottomLeft = CGPoint(x: rectFeature.bottomLeft.y * imageScale, y: rectFeature.bottomLeft.x * imageScale)
            
            path = UIBezierPath()
            path?.move(to: newTopLeft)
            path?.addLine(to: newTopRight)
            path?.addLine(to: newBottomRight)
            path?.addLine(to: newBottomLeft)
            path?.close()
            
            if isAutoCaptureEnabled {
                quadLayer.path = path?.cgPath
                guard let boundingBox = quadLayer.path?.boundingBox else {
                    return
                }
                autoCaptureAssist(rect: boundingBox)
            } else {
                quadLayer.path = nil
            }
        }
    }
}

extension ChildViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(), let image = UIImage(data: imageData) else {
            return
        }
    }
}

extension ChildViewController {
    public func enableAutoCapture(enabled: Bool){
        isAutoCaptureEnabled = enabled
        
    }
}

protocol ChildViewControllerDelegate: class {
    func childViewController(childViewController: ChildViewController)
}
