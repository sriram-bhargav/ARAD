import UIKit
import SceneKit
import ARKit

import Vision

class ViewController: UIViewController, ARSCNViewDelegate {
    
    @IBOutlet var sceneView: ARSCNView!
    let bubbleDepth : Float = 0.01
    var latestPrediction : String = "…"
    
    var visionRequests = [VNRequest]()
    let dispatchQueueML = DispatchQueue(label: "com.hw.dispatchqueueml") // A Serial Queue
    @IBOutlet weak var debugTextView: UITextView!
    
    var adWordsUsed = [String: Bool]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sceneView.delegate = self
        sceneView.showsStatistics = true
        let scene = SCNScene()
        sceneView.scene = scene
        sceneView.autoenablesDefaultLighting = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(gestureRecognize:)))
        view.addGestureRecognizer(tap)

        // load model and init CoreML.
        guard let inceptionV3Model = try? VNCoreMLModel(for: Inceptionv3().model) else {
            fatalError("Could not load model")
        }
        let classificationRequest = VNCoreMLRequest(
            model: inceptionV3Model, completionHandler: classificationCompleteHandler)
        classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop
        visionRequests = [classificationRequest]

        loopCoreMLUpdate()
    }
    
    func loopCoreMLUpdate() {
        dispatchQueueML.async {
            self.updateCoreML()
            self.loopCoreMLUpdate()
        }
    }

    func updateCoreML() {
        let pixbuff : CVPixelBuffer? = (sceneView.session.currentFrame?.capturedImage)
        if pixbuff == nil { return }
        let ciImage = CIImage(cvPixelBuffer: pixbuff!)
        // Prepare CoreML/Vision Request
        let imageRequestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try imageRequestHandler.perform(self.visionRequests)
        } catch {
            print(error)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            // Do any desired updates to SceneKit here.
        }
    }

    override var prefersStatusBarHidden : Bool {
        return true
    }

    @objc func handleTap(gestureRecognize: UITapGestureRecognizer) {
        runAd()
    }
    
    func runAd() {
        if adWordsUsed[latestPrediction.lowercased()] == nil {
            // Get Screen Centre
            let screenCentre : CGPoint = CGPoint(x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY)
            
            let results : [ARHitTestResult] = self.sceneView.hitTest(
                screenCentre, types: [.featurePoint, .existingPlaneUsingExtent])
            
            if let closestResult = results.first {
                // Get Coordinates of HitTest
                let transform : matrix_float4x4 = closestResult.worldTransform
                let worldCoord : SCNVector3 = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                
                // Create 3D Text
                let node : SCNNode = createNewBubbleParentNode(latestPrediction)
                adWordsUsed[latestPrediction.lowercased()] = true
                sceneView.scene.rootNode.addChildNode(node)
                node.position = worldCoord
            }
        }
    }
    
    func createNewBubbleParentNode(_ text : String) -> SCNNode {
        // Warning: Creating 3D Text is susceptible to crashing. To reduce chances of crashing; reduce number of polygons, letters, smoothness, etc.
        
        // TEXT BILLBOARD CONSTRAINT
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = SCNBillboardAxis.Y
        
        // BUBBLE-TEXT
        let bubble = SCNText(string: text, extrusionDepth: CGFloat(bubbleDepth))
        var font = UIFont(name: "Futura", size: 0.15)
        font = font?.withTraits(traits: .traitBold)
        bubble.font = font
        bubble.alignmentMode = kCAAlignmentCenter
        bubble.firstMaterial?.diffuse.contents = UIColor.orange
        bubble.firstMaterial?.specular.contents = UIColor.white
        bubble.firstMaterial?.isDoubleSided = true
        // bubble.flatness // setting this too low can cause crashes.
        bubble.chamferRadius = CGFloat(bubbleDepth)
        
        // BUBBLE NODE
        let (minBound, maxBound) = bubble.boundingBox
        let bubbleNode = SCNNode(geometry: bubble)
        // Centre Node - to Centre-Bottom point
        bubbleNode.pivot = SCNMatrix4MakeTranslation( (maxBound.x - minBound.x)/2, minBound.y, bubbleDepth/2)
        // Reduce default text size
        bubbleNode.scale = SCNVector3Make(0.2, 0.2, 0.2)
        
        // CENTRE POINT NODE
        let sphere = SCNSphere(radius: 0.005)
        sphere.firstMaterial?.diffuse.contents = UIColor.cyan
        let sphereNode = SCNNode(geometry: sphere)
        
        // BUBBLE PARENT NODE
        let bubbleNodeParent = SCNNode()
        bubbleNodeParent.addChildNode(bubbleNode)
        bubbleNodeParent.addChildNode(sphereNode)
        bubbleNodeParent.constraints = [billboardConstraint]
        
        return bubbleNodeParent
    }
    
    func classificationCompleteHandler(request: VNRequest, error: Error?) {
        if error != nil {
            print("Error: " + (error?.localizedDescription)!)
            return
        }
        guard let observations = request.results else {
            print("No results")
            return
        }

        // Get Classifications
        let classifications = observations[0...1] // top 2 results
            .flatMap({ $0 as? VNClassificationObservation })
            .map({ "\($0.identifier) \(String(format:"- %.2f", $0.confidence))" })
            .joined(separator: "\n")

        DispatchQueue.main.async {
            print(classifications)
            print("--")

            var debugText:String = ""
            debugText += classifications
            self.debugTextView.text = debugText
            
            // Store the latest prediction
            var objectName:String = "…"
            objectName = classifications.components(separatedBy: "-")[0]
            objectName = objectName.components(separatedBy: ",")[0]
            self.latestPrediction = objectName
        }
    }
}

extension UIFont {
    func withTraits(traits:UIFontDescriptorSymbolicTraits...) -> UIFont {
        let descriptor = self.fontDescriptor.withSymbolicTraits(UIFontDescriptorSymbolicTraits(traits))
        return UIFont(descriptor: descriptor!, size: 0)
    }
}
