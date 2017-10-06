//
//  ViewController.swift
//  AVFilterTest
//
//  Created by Haruya Ishikawa on 2017/10/05.
//  Copyright © 2017 Haruya Ishikawa. All rights reserved.
//

import UIKit

// MARK: - Not really used
import SceneKit
import ARKit

// MARK: - Import for AV Editing
import CoreImage
import AVFoundation
import GLKit


class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate{
    
    // MARK: - Properties
    var videoPreviewView: GLKView?
    var ciContext: CIContext?
    var eaglContext: EAGLContext?
    var videoPreviewViewBounds = CGRect.zero
    
    // MARK: - AV related
    var videoDevice: AVCaptureDevice?
    var captureSession: AVCaptureSession?
    var captureSessionQueue = DispatchQueue(label: "capture_session_queue")
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Remove the view's background color; this allows us not to use the opaque propety
        // (self.view.opaque = false) since we remove the background color drawing altogether
        self.view.backgroundColor = UIColor.clear
        // setup the GLKView for video/image preview
        let window: UIView? = ((UIApplication.shared.delegate)?.window)!
        eaglContext = EAGLContext(api: .openGLES2)
        videoPreviewView = GLKView(frame: (window?.bounds)!, context: eaglContext!)
        videoPreviewView?.enableSetNeedsDisplay = false
        
        // Because the native video image from the back camera is in UIDeviceOrientationLandscapeLeft
        // (i.e. the home button is on the right), we need to apply a clockwise 90 degree transform
        // so that we can draw the video preview as if we were in a landscape-oriented view;
        // if you're using the front camera and you want to have a mirrored preview
        // (so that the user is seeing themselves in the mirror), you need to apply an additional
        // horizontal flip (by concatenating CGAffineTransformMakeScale(-1.0, 1.0) to the rotation transform)
        videoPreviewView?.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2))
        videoPreviewView?.frame = (window?.bounds)!
        
        // We make our video preview view a subview of the window, and send it to the back;
        // this makes ViewController's view (and its UI elements) on top of the video preview,
        // and also makes video preview unaffected by device rotation
        window?.addSubview(videoPreviewView!)
        window?.sendSubview(toBack: videoPreviewView!)
        
        // Bind the frame buffer to get the frame buffer width and height;
        // the bounds used by CIContext when drawing to a GLKView are in pixels (not points),
        // hence the need to read from the frame buffer's width and height;
        // in addition, since we will be accessing the bounds in another queue (_captureSessionQueue),
        // we want to obtain this piece of information so that we won't be
        // accessing _videoPreviewView's properties from another thread/queue
        videoPreviewView?.bindDrawable()
        videoPreviewViewBounds = CGRect.zero
        videoPreviewViewBounds.size.width = CGFloat((videoPreviewView?.drawableWidth)!)
        videoPreviewViewBounds.size.height = CGFloat((videoPreviewView?.drawableHeight)!)
        
        // Create the CIContext instance, note that this must be done after _videoPreviewView is properly set up
        ciContext = CIContext(eaglContext: eaglContext!, options: [kCIContextWorkingColorSpace: NSNull()])
        if AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera], mediaType: .video, position: .back).devices.count > 0 {
            self.start()
        }
        else {
            print("No device with AVMediaTypeVideo")
        }

        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    // Start camera
    func start() {
        
        let videoDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera], mediaType: .video, position: .back).devices
        let position: AVCaptureDevice.Position = .back
        
        // Get back camera
        for device in videoDevices {
            if device.position == position {
                videoDevice = device
                break
            }
        }
        
        // Obtain camera input
        let error: Error? = nil
        let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice!)
        if videoDeviceInput == nil {
            print("Unable to obtain video device input, error: \(error!)")
            return
        }
        
        // Obtain the preset and validate the preset
        let preset: AVCaptureSession.Preset = .medium
        if !((videoDevice?.supportsSessionPreset(preset))!) {
            print("\("Capture session preset not supported by video device: \(preset)")")
            return
        }
        
        // Create the capture session
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = preset
        
        // CoreImage wants BGRA pixel format
        let outputSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        // Create and configure video data output
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = outputSettings
        
        // Call delegate -> filter (in delegateQueue)
        videoDataOutput.setSampleBufferDelegate(self as AVCaptureVideoDataOutputSampleBufferDelegate, queue: captureSessionQueue)
        
        // Always discard late video frames
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        // Begin configure capture session
        captureSession?.beginConfiguration()
        if !(captureSession?.canAddOutput(videoDataOutput))! {
            print("Cannot add video data output")
            captureSession = nil
            return
        }
        
        // Connect the video device input and video data and still image outputs
        captureSession?.addInput(videoDeviceInput!)
        captureSession?.addOutput(videoDataOutput)
        captureSession?.commitConfiguration()
        
        // Then start everything
        captureSession?.startRunning()
        
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let imageBuffer: CVImageBuffer? = CMSampleBufferGetImageBuffer(sampleBuffer)
        let sourceImage = CIImage(cvPixelBuffer: imageBuffer!, options: nil)
        let sourceExtent: CGRect = sourceImage.extent
        
        // Image processing -> Filters
//        let vignetteFilter = CIFilter(name: "CIVignetteEffect")
//        vignetteFilter?.setValue(sourceImage, forKey: kCIInputImageKey)
//        vignetteFilter?.setValue(CIVector(x: sourceExtent.size.width / 2, y: sourceExtent.size.height / 2), forKey: kCIInputCenterKey)
//        vignetteFilter?.setValue((sourceExtent.size.width / 2), forKey: kCIInputRadiusKey)
//        var filteredImage: CIImage? = vignetteFilter?.outputImage

        let sepiaFilter = CIFilter(name: "CISepiaTone")
        sepiaFilter?.setValue(0.8, forKey: kCIInputIntensityKey)
        sepiaFilter?.setValue(sourceImage, forKey: kCIInputImageKey) // First filter always needs input!
        var filteredImage: CIImage? = sepiaFilter?.outputImage
        
        
        let effectFilter = CIFilter(name: "CIPhotoEffectInstant")
        effectFilter?.setValue(filteredImage, forKey: kCIInputImageKey)
        filteredImage = effectFilter?.outputImage
        
        // Display
        let sourceAspect: CGFloat = sourceExtent.size.width / sourceExtent.size.height
        let previewAspect: CGFloat = videoPreviewViewBounds.size.width / videoPreviewViewBounds.size.height
        // we want to maintain the aspect radio of the screen size, so we clip the video image
        var drawRect: CGRect = sourceExtent
        if sourceAspect > previewAspect {
            // use full height of the video image, and center crop the width
            drawRect.origin.x += (drawRect.size.width - drawRect.size.height * previewAspect) / 2.0
            drawRect.size.width = drawRect.size.height * previewAspect
        }
        else {
            // use full width of the video image, and center crop the height
            drawRect.origin.y += (drawRect.size.height - drawRect.size.width / previewAspect) / 2.0
            drawRect.size.height = drawRect.size.width / previewAspect
        }
        
        videoPreviewView?.bindDrawable()
        if eaglContext != EAGLContext.current() {
            EAGLContext.setCurrent(eaglContext)
        }
        // clear eagl view to grey
        glClearColor(0.5, 0.5, 0.5, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        // set the blend mode to "source over" so that CI will use that
        glEnable(GLenum(GL_BLEND))
        glBlendFunc(GLenum(GL_ONE), GLenum(GL_ONE_MINUS_SRC_ALPHA))
        if (filteredImage != nil) {
            ciContext?.draw(filteredImage!, in: videoPreviewViewBounds, from: drawRect)
        }
        videoPreviewView?.display()
        
    }
    
    
}
