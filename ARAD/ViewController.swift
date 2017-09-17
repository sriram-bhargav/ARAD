import UIKit
import SceneKit
import ARKit
import Alamofire

import Vision

class ViewController: UIViewController, ARSCNViewDelegate {
    
    @IBOutlet var sceneView: ARSCNView!
    let bubbleDepth : Float = 0.01
    var latestPrediction : String = ""
    
    var visionRequests = [VNRequest]()
    let dispatchQueue = DispatchQueue(label: "") // A Serial Queue
    let modelThreshold:Double = 0.2
    @IBOutlet weak var debugTextView: UITextView!
    
    var adWordsUsed = [String: Bool]()
    var adIds = [String: String]()

    // Try to show ads every 5 mins. Can be adjusted by the developer.
    var delay:Double = 150.0
    var countdownTimer = Timer()
    // Sends batch requests every 0.5 seconds for 5 seconds
    var adTimer = Timer()
    var adTimeLimit:Double = 10.0
    
    var tempAdWordLocation = [String: SCNVector3]()
    var tempAdWords = [String]()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.scheduledTimerWithTimeInterval()
        sceneView.delegate = self
        sceneView.showsStatistics = true
        let scene = SCNScene()
        sceneView.scene = scene
        sceneView.autoenablesDefaultLighting = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(gestureRecognizer:)))
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
    
    func scheduledTimerWithTimeInterval(){
        adTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(self.invokeAdServer), userInfo: nil, repeats: true)
    }
    
    func scheduledDelayTimerWithTimeInterval(){
        countdownTimer = Timer.scheduledTimer(timeInterval: delay, target: self, selector: #selector(self.reinitAdServer), userInfo: nil, repeats: false)
    }

    @objc func reinitAdServer() {
        adTimeLimit = 5.0
        scheduledTimerWithTimeInterval()
    }
    
    func contactARADServer() {
        if tempAdWords.count > 0 {
            makeRequest(keywords: tempAdWords)
        }
    }
    
    func clearTempAdWords() {
        tempAdWords = []
        tempAdWordLocation = [:]
    }
    
    @objc func invokeAdServer() {
        adTimeLimit -= 0.5
        if adTimeLimit <= 0 {
            contactARADServer()
            adTimer.invalidate()
            scheduledDelayTimerWithTimeInterval()
        } else {
            countdownTimer.invalidate()
            runAd()
        }
    }
    
    func loopCoreMLUpdate() {
        dispatchQueue.async {
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

    @objc func handleTap(gestureRecognizer: UITapGestureRecognizer) {
        runAd()
    }
    
    func runAd() {
        print(1)
        latestPrediction = latestPrediction.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if latestPrediction != "" && adWordsUsed[latestPrediction] == nil {
            // Get Screen Centre
            let screenCentre : CGPoint = CGPoint(x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY)
            let results : [ARHitTestResult] = self.sceneView.hitTest(screenCentre, types: [.featurePoint])

            if let closestResult = results.first {
                // Get Coordinates of HitTest
                let transform : matrix_float4x4 = closestResult.worldTransform
                let worldCoord: SCNVector3 = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                print(latestPrediction)
                tempAdWordLocation[latestPrediction] = worldCoord
                tempAdWords.append(latestPrediction)
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
   
    func captureReaction(adId: String, isClick: Bool) {
        let parameters: Parameters = [
            "id": adId,
            "is_click": isClick,
        ]
        Alamofire.request("https://yesteapea.com/arad/reaction", method: .post, parameters: parameters, encoding: JSONEncoding.default)
            .responseJSON { response in }
    }
    
    func makeRequest(keywords: [String]) {
        let parameters: Parameters = [
            "tags": keywords
        ]
        Alamofire.request("https://yesteapea.com/arad/getads", method: .post, parameters: parameters, encoding: JSONEncoding.default)
            .responseJSON { response in
                print(response)
                //to get status code
                if let status = response.response?.statusCode {
                    switch(status) {
                    case 200:
                        print("success")
                    default:
                        print("not success")
                    }
                }
                if let result = response.result.value {
                    let results = result as! NSArray
                    if results.count > 0 {
                        let firstResult = results[0]
                        let adResult = firstResult as! [String: AnyObject]
                        print(adResult)
                        print(adResult["requested_tag"] as! String)
                        // Create 3D Text
                        let topAdWord = adResult["requested_tag"] as! String
                        let node : SCNNode = self.createNewBubbleParentNode(topAdWord)
                        node.position = self.tempAdWordLocation[topAdWord]!
                        self.sceneView.scene.rootNode.addChildNode(node)
                        self.adWordsUsed[topAdWord] = true
                        let adId = adResult["id"] as! String
                        // Save Ad id for click tracking.
                        self.adIds.updateValue(adId, forKey: topAdWord)
                        // Send ARAD server to update impression.
                        self.captureReaction(adId: adId, isClick: false)
                    }
                }
                self.clearTempAdWords()
        }
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
            // print(classifications)
            // print("--")

            var debugText:String = ""
            debugText += classifications
            self.debugTextView.text = debugText
            
            // Store the latest prediction
            var objectName:String = ""
            objectName = classifications.components(separatedBy: " - ")[0]
            objectName = objectName.components(separatedBy: ",")[0]
            if let doubleScore = Double(classifications.components(separatedBy: " - ")[1]) {
                if doubleScore >= self.modelThreshold {
                    self.latestPrediction = objectName
                    print(objectName)
                }
            }
        }
    }
}

extension UIFont {
    func withTraits(traits:UIFontDescriptorSymbolicTraits...) -> UIFont {
        let descriptor = self.fontDescriptor.withSymbolicTraits(UIFontDescriptorSymbolicTraits(traits))
        return UIFont(descriptor: descriptor!, size: 0)
    }
}
