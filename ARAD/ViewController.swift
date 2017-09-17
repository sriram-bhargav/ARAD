import UIKit
import SceneKit
import ARKit
import Alamofire

import Vision

class ViewController: UIViewController, ARSCNViewDelegate {
    
    @IBOutlet weak var planeSearchLabel: UILabel!
    @IBOutlet weak var planeSearchOverlay: UIView!
    
    @IBOutlet weak var gameStateLabel: UILabel!
    @IBAction func didTapStartOver(_ sender: Any) { reset() }
    
    @IBOutlet weak var sceneView: ARSCNView!
    
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
    
    
    // Mark - game
    
    // GAME
    
    private func updatePlaneOverlay() {
        DispatchQueue.main.async {
            self.planeSearchOverlay.isHidden = self.currentPlane != nil
            
            if self.planeCount == 0 {
                self.planeSearchLabel.text = "Move around to allow the app the find a plane..."
            } else {
                self.planeSearchLabel.text = "Tap on a plane surface to place board..."
            }
            
        }
    }
    
    var playerType = [
        GamePlayer.x: GamePlayerType.human,
        GamePlayer.o: GamePlayerType.ai
    ]
    var planeCount = 0 {
        didSet {
            updatePlaneOverlay()
        }
    }
    var currentPlane:SCNNode? {
        didSet {
            updatePlaneOverlay()
            newTurn()
        }
    }
    let board = Board()
    var game:GameState! {
        didSet {
            if (gameStateLabel == nil) {
                return
            }
            gameStateLabel.text = game.currentPlayer.rawValue + ":" + playerType[game.currentPlayer]!.rawValue.uppercased() + " to " + game.mode.rawValue
            
            if let winner = game.currentWinner {
                let alert = UIAlertController(title: "Game Over", message: "\(winner.rawValue) wins!!!!", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { action in
                    self.reset()
                }))
                present(alert, animated: true, completion: nil)
            } else {
                if currentPlane != nil {
                    newTurn()
                }
            }
        }
    }
    
    private func reset() {
        let alert = UIAlertController(title: "Game type", message: "Choose players", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "x:HUMAN vs o:AI", style: .default, handler: { action in
            self.beginNewGame([
                GamePlayer.x: GamePlayerType.human,
                GamePlayer.o: GamePlayerType.ai
                ])
        }))
        alert.addAction(UIAlertAction(title: "x:HUMAN vs o:HUMAN", style: .default, handler: { action in
            self.beginNewGame([
                GamePlayer.x: GamePlayerType.human,
                GamePlayer.o: GamePlayerType.human
                ])
        }))
        alert.addAction(UIAlertAction(title: "x:AI vs o:AI", style: .default, handler: { action in
            self.beginNewGame([
                GamePlayer.x: GamePlayerType.ai,
                GamePlayer.o: GamePlayerType.ai
                ])
        }))
        present(alert, animated: true, completion: nil)
        
    }
    
    private func beginNewGame(_ players:[GamePlayer:GamePlayerType]) {
        playerType = players
        game = GameState()
        
        removeAllFigures()
        
        figures.removeAll()
    }
    
    private func newTurn() {
        guard playerType[game.currentPlayer]! == .ai else { return }
        
        //run AI on background thread
        DispatchQueue.global(qos: DispatchQoS.QoSClass.background).async {
            // let the AI determine which action to perform
            let action = GameAI(game: self.game).bestAction
            
            // once an action has been determined, perform it on main thread
            DispatchQueue.main.async {
                // perform action or crash (game AI should never return an invalid action!)
                guard let newGameState = self.game.perform(action: action) else { fatalError() }
                
                // block to execute after we have updated/animated the visual state of the game
                let updateGameState = {
                    // for some reason we have to put this in a main.async block in order to actually
                    // get to main thread. It appears that SceneKit animations do not return on mainthread..
                    DispatchQueue.main.async {
                        self.game = newGameState
                    }
                }
                
                // animate action
                switch action {
                case .put(let at):
                    self.put(piece: Figure.figure(for: self.game.currentPlayer),
                             at: at,
                             completionHandler: updateGameState)
                    
                case .move(let from, let to):
                    self.move(from: from,
                              to: to,
                              completionHandler: updateGameState)
                }
                
            }
        }
    }
    
    private func removeAllFigures() {
        for (_, figure) in figures {
            figure.removeFromParentNode()
        }
    }
    
    private func restoreGame(at position:SCNVector3) {
        board.node.position = position
        sceneView.scene.rootNode.addChildNode(board.node)
        
        let light = SCNLight()
        light.type = .directional
        light.castsShadow = true
        light.shadowRadius = 200
        light.shadowColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.3)
        light.shadowMode = .deferred
        let constraint = SCNLookAtConstraint(target: board.node)
        lightNode = SCNNode()
        lightNode!.light = light
        lightNode!.position = SCNVector3(position.x + 10, position.y + 10, position.z)
        // lightNode!.eulerAngles = SCNVector3(45.0.degreesToRadians, 0, 0)
        lightNode!.constraints = [constraint]
        sceneView.scene.rootNode.addChildNode(lightNode!)
        
        
        for (key, figure) in figures {
            // yeah yeah, I know I should turn GamePosition into a struct and provide it with
            // Equtable and Hashable then this stupid stringy stuff would be gone. Will do this eventually
            let xyComponents = key.components(separatedBy: "x")
            guard xyComponents.count == 2,
                let x = Int(xyComponents[0]),
                let y = Int(xyComponents[1]) else { fatalError() }
            put(piece: figure,
                at: (x: x,
                     y: y))
        }
    }
    
    private func groundPositionFrom(location:CGPoint) -> SCNVector3? {
        let results = sceneView.hitTest(location,
                                        types: ARHitTestResult.ResultType.existingPlaneUsingExtent)
        
        guard results.count > 0 else { return nil }
        
        return SCNVector3.positionFromTransform(results[0].worldTransform)
    }
    
    private func anyPlaneFrom(location:CGPoint) -> (SCNNode, SCNVector3)? {
        let results = sceneView.hitTest(location,
                                        types: ARHitTestResult.ResultType.existingPlaneUsingExtent)
        
        guard results.count > 0,
            let anchor = results[0].anchor,
            let node = sceneView.node(for: anchor) else { return nil }
        
        return (node, SCNVector3.positionFromTransform(results[0].worldTransform))
    }
    
    private func squareFrom(location:CGPoint) -> ((Int, Int), SCNNode)? {
        guard let _ = currentPlane else { return nil }
        
        let hitResults = sceneView.hitTest(location, options: [SCNHitTestOption.firstFoundOnly: false,
                                                               SCNHitTestOption.rootNode:       board.node])
        
        for result in hitResults {
            if let square = board.nodeToSquare[result.node] {
                return (square, result.node)
            }
        }
        
        return nil
    }
    
    private func revertDrag() {
        if let draggingFrom = draggingFrom {
            
            let restorePosition = sceneView.scene.rootNode.convertPosition(draggingFromPosition!, from: board.node)
            let action = SCNAction.move(to: restorePosition, duration: 0.3)
            figures["\(draggingFrom.x)x\(draggingFrom.y)"]?.runAction(action)
            
            self.draggingFrom = nil
            self.draggingFromPosition = nil
        }
    }
    
    /// animates AI moving a piece
    private func move(from:GamePosition,
                      to:GamePosition,
                      completionHandler: (() -> Void)? = nil) {
        
        let fromSquareId = "\(from.x)x\(from.y)"
        let toSquareId = "\(to.x)x\(to.y)"
        guard let piece = figures[fromSquareId],
            let rawDestinationPosition = board.squareToPosition[toSquareId]  else { fatalError() }
        
        // this stuff will change once we stop putting nodes directly in world space..
        let destinationPosition = sceneView.scene.rootNode.convertPosition(rawDestinationPosition,
                                                                           from: board.node)
        
        // update visual game state
        figures[toSquareId] = piece
        figures[fromSquareId] = nil
        
        // create drag and drop animation
        let pickUpAction = SCNAction.move(to: SCNVector3(piece.position.x, piece.position.y + Float(Dimensions.DRAG_LIFTOFF), piece.position.z),
                                          duration: 0.25)
        let moveAction = SCNAction.move(to: SCNVector3(destinationPosition.x, destinationPosition.y + Float(Dimensions.DRAG_LIFTOFF), destinationPosition.z),
                                        duration: 0.5)
        let dropDownAction = SCNAction.move(to: destinationPosition,
                                            duration: 0.25)
        
        // run drag and drop animation
        piece.runAction(pickUpAction) {
            piece.runAction(moveAction) {
                piece.runAction(dropDownAction,
                                completionHandler: completionHandler)
            }
        }
    }
    
    /// renders user and AI insert of piece
    private func put(piece:SCNNode,
                     at position:GamePosition,
                     completionHandler: (() -> Void)? = nil) {
        let squareId = "\(position.x)x\(position.y)"
        guard let squarePosition = board.squareToPosition[squareId] else { fatalError() }
        
        piece.opacity = 0  // initially invisible
        // // https://stackoverflow.com/questions/30392579/convert-local-coordinates-to-scene-coordinates-in-scenekit
        piece.position = sceneView.scene.rootNode.convertPosition(squarePosition,
                                                                  from: board.node)
        sceneView.scene.rootNode.addChildNode(piece)
        figures[squareId] = piece
        
        let action = SCNAction.fadeIn(duration: 0.5)
        piece.runAction(action,
                        completionHandler: completionHandler)
    }
    
    
    var figures:[String:SCNNode] = [:]
    var lightNode:SCNNode?
    var floorNode:SCNNode?
    var draggingFrom:GamePosition? = nil
    var draggingFromPosition:SCNVector3? = nil
    // from demo APP
    // Use average of recent virtual object distances to avoid rapid changes in object scale.
    var recentVirtualObjectDistances = [CGFloat]()
    var tempAdWordLocation = [String: SCNVector3]()
    var tempAdWords = [String]()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.scheduledTimerWithTimeInterval()
        
        game = GameState()  // create new game
        
        sceneView.delegate = self
        sceneView.antialiasingMode = .multisampling4X
        //sceneView.showsStatistics = true
        
        let scene = SCNScene()
        sceneView.scene = scene
        sceneView.autoenablesDefaultLighting = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(gestureRecognizer:)))
        view.addGestureRecognizer(tap)
        
        
        let pan = UIPanGestureRecognizer()
        pan.addTarget(self, action: #selector(didPan))
        sceneView.addGestureRecognizer(pan)

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
    
    // MARK: - Gestures
    
    @objc func didPan(_ sender:UIPanGestureRecognizer) {
        guard case .move = game.mode,
            playerType[game.currentPlayer]! == .human else { return }
        
        let location = sender.location(in: sceneView)
        
        switch sender.state {
        case .began:
            print("begin \(location)")
            guard let square = squareFrom(location: location) else { return }
            draggingFrom = (x: square.0.0, y: square.0.1)
            draggingFromPosition = square.1.position
            
        case .cancelled:
            print("cancelled \(location)")
            revertDrag()
            
        case .changed:
            print("changed \(location)")
            guard let draggingFrom = draggingFrom,
                let groundPosition = groundPositionFrom(location: location) else { return }
            
            let action = SCNAction.move(to: SCNVector3(groundPosition.x, groundPosition.y + Float(Dimensions.DRAG_LIFTOFF), groundPosition.z),
                                        duration: 0.1)
            figures["\(draggingFrom.x)x\(draggingFrom.y)"]?.runAction(action)
            
        case .ended:
            print("ended \(location)")
            
            guard let draggingFrom = draggingFrom,
                let square = squareFrom(location: location),
                square.0.0 != draggingFrom.x || square.0.1 != draggingFrom.y,
                let newGameState = game.perform(action: .move(from: draggingFrom,
                                                              to: (x: square.0.0, y: square.0.1))) else {
                                                                revertDrag()
                                                                return
            }
            
            
            
            // move in visual model
            let toSquareId = "\(square.0.0)x\(square.0.1)"
            figures[toSquareId] = figures["\(draggingFrom.x)x\(draggingFrom.y)"]
            figures["\(draggingFrom.x)x\(draggingFrom.y)"] = nil
            self.draggingFrom = nil
            
            // copy pasted insert thingie
            let newPosition = sceneView.scene.rootNode.convertPosition(square.1.position,
                                                                       from: square.1.parent)
            let action = SCNAction.move(to: newPosition,
                                        duration: 0.1)
            figures[toSquareId]?.runAction(action) {
                DispatchQueue.main.async {
                    self.game = newGameState
                }
            }
            
        case .failed:
            print("failed \(location)")
            revertDrag()
            
        default: break
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
        configuration.isLightEstimationEnabled = true
        
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
    
    // from APples app
    func enableEnvironmentMapWithIntensity(_ intensity: CGFloat) {
        if sceneView.scene.lightingEnvironment.contents == nil {
            if let environmentMap = UIImage(named: "Media.scnassets/environment_blur.exr") {
                sceneView.scene.lightingEnvironment.contents = environmentMap
            }
        }
        sceneView.scene.lightingEnvironment.intensity = intensity
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            // Do any desired updates to SceneKit here.
            // If light estimation is enabled, update the intensity of the model's lights and the environment map
            if let lightEstimate = self.sceneView.session.currentFrame?.lightEstimate {
                
                // Apple divived the ambientIntensity by 40, I find that, atleast with the materials used
                // here that it's a big too bright, so I increased to to 50..
                self.enableEnvironmentMapWithIntensity(lightEstimate.ambientIntensity / 50)
            } else {
                self.enableEnvironmentMapWithIntensity(25)
            }
        }
    }
    
    // did at plane(?)
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        planeCount += 1
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        if node == currentPlane {
            removeAllFigures()
            lightNode?.removeFromParentNode()
            lightNode = nil
            floorNode?.removeFromParentNode()
            floorNode = nil
            board.node.removeFromParentNode()
            currentPlane = nil
        }
        
        if planeCount > 0 {
            planeCount -= 1
        }
    }

    override var prefersStatusBarHidden : Bool {
        return true
    }

    @objc func handleTap(gestureRecognizer: UITapGestureRecognizer) {
        let location = gestureRecognizer.location(in: sceneView)
        
        // tap to place board..
        guard let _ = currentPlane else {
            guard let newPlaneData = anyPlaneFrom(location: location) else { return }
            
            let floor = SCNFloor()
            floor.reflectivity = 0
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.white
            
            // https://stackoverflow.com/questions/30975695/scenekit-is-it-possible-to-cast-an-shadow-on-an-transparent-object/44799498#44799498
            material.colorBufferWriteMask = SCNColorMask(rawValue: 0)
            floor.materials = [material]
            
            floorNode = SCNNode(geometry: floor)
            floorNode!.position = newPlaneData.1
            sceneView.scene.rootNode.addChildNode(floorNode!)
            
            self.currentPlane = newPlaneData.0
            restoreGame(at: newPlaneData.1)
            
            return
        }
        
        // otherwise tap to place board piece.. (if we're in "put" mode)
        guard case .put = game.mode,
            playerType[game.currentPlayer]! == .human else { return }
        
        if let squareData = squareFrom(location: location),
            let newGameState = game.perform(action: .put(at: (x: squareData.0.0,
                                                              y: squareData.0.1))) {
            
            put(piece: Figure.figure(for: game.currentPlayer),
                at: squareData.0) {
                    DispatchQueue.main.async {
                        self.game = newGameState
                    }
            }
        }
        //runAd()
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
