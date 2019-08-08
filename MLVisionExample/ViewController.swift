//
//  Copyright (c) 2018 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import UIKit
import Firebase

/// Main view controller class.
@objc(ViewController)
class ViewController:  UIViewController, UINavigationControllerDelegate {
    
  /// Firebase vision instance.
  // [START init_vision]
  lazy var vision = Vision.vision()
  // [END init_vision]

  /// Manager for local and remote models.
  lazy var modelManager = ModelManager.modelManager()

  /// Whether the AutoML models are registered.
  var areAutoMLModelsRegistered = false

  /// A string holding current results from detection.
  var resultsText = ""

  /// An overlay view that displays detection annotations.
  private lazy var annotationOverlayView: UIView = {
    precondition(isViewLoaded)
    let annotationOverlayView = UIView(frame: .zero)
    annotationOverlayView.translatesAutoresizingMaskIntoConstraints = false
    return annotationOverlayView
  }()

  /// An image picker for accessing the photo library or camera.
  var imagePicker = UIImagePickerController()

  // MARK: - IBOutlets

  // @IBOutlet fileprivate weak var detectorPicker: UIPickerView!
  @IBOutlet weak var numOfPeopleLabel: UILabel!
  @IBOutlet weak var numOfPeoplePicker: UIPickerView!
  @IBOutlet weak var counterNoP: UILabel!
  @IBOutlet weak var photoToolbar: UIToolbar!
  @IBOutlet weak var detectToolbar: UIToolbar!
  @IBOutlet fileprivate weak var imageView: UIImageView!
  @IBOutlet fileprivate weak var photoCameraButton: UIBarButtonItem!
  @IBOutlet weak var detectButton: UIBarButtonItem!
  @IBOutlet var downloadProgressView: UIProgressView!
    
  let numsOfPeople = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20]
  var numOfPeople = 0

  // MARK: - UIViewController

  override func viewDidLoad() {
    super.viewDidLoad()
    
    self.numOfPeoplePicker.delegate = self
    self.numOfPeoplePicker.dataSource = self

    imageView.addSubview(annotationOverlayView)
    NSLayoutConstraint.activate([
      annotationOverlayView.topAnchor.constraint(equalTo: imageView.topAnchor),
      annotationOverlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
      annotationOverlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
      annotationOverlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
      ])

    imagePicker.delegate = self
    imagePicker.sourceType = .photoLibrary

    let isCameraAvailable = UIImagePickerController.isCameraDeviceAvailable(.front) ||
      UIImagePickerController.isCameraDeviceAvailable(.rear)
    if isCameraAvailable {
      // `CameraViewController` uses `AVCaptureDevice.DiscoverySession` which is only supported for
    } else {
      photoCameraButton.isEnabled = false
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    navigationController?.navigationBar.isHidden = true
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)

    navigationController?.navigationBar.isHidden = false
  }

  // MARK: - IBActions

  @IBAction func detect(_ sender: Any) {
    clearResults()
    detectTextOnDevice(image: imageView.image)
    }

  @IBAction func openPhotoLibrary(_ sender: Any) {
    imagePicker.sourceType = .photoLibrary
    present(imagePicker, animated: true)
  }

  @IBAction func openCamera(_ sender: Any) {
    guard UIImagePickerController.isCameraDeviceAvailable(.front) ||
      UIImagePickerController.isCameraDeviceAvailable(.rear)
      else {
        return
    }
    imagePicker.sourceType = .camera
    present(imagePicker, animated: true)
  }

  // MARK: - Private

  /// Removes the detection annotations from the annotation overlay view.
  private func removeDetectionAnnotations() {
    for annotationView in annotationOverlayView.subviews {
      annotationView.removeFromSuperview()
    }
  }

  /// Clears the results text view and removes any frames that are visible.
  private func clearResults() {
    removeDetectionAnnotations()
    self.resultsText = ""
  }

  /// Updates the image view with a scaled version of the given image.
  private func updateImageView(with image: UIImage) {
    let orientation = UIApplication.shared.statusBarOrientation
    var scaledImageWidth: CGFloat = 0.0
    var scaledImageHeight: CGFloat = 0.0
    switch orientation {
        case .portrait, .portraitUpsideDown, .unknown:
          scaledImageWidth = imageView.bounds.size.width
          scaledImageHeight = image.size.height * scaledImageWidth / image.size.width
        case .landscapeLeft, .landscapeRight:
          scaledImageWidth = image.size.width * scaledImageHeight / image.size.height
          scaledImageHeight = imageView.bounds.size.height
    }
    DispatchQueue.global(qos: .userInitiated).async {
      // Scale image while maintaining aspect ratio so it displays better in the UIImageView.
      var scaledImage = image.scaledImage(
        with: CGSize(width: scaledImageWidth, height: scaledImageHeight)
      )
      scaledImage = scaledImage ?? image
      guard let finalImage = scaledImage else { return }
      DispatchQueue.main.async {
        self.imageView.image = finalImage
        
        print("image", self.imageView.image)
        // if there is an image present, hide numofpeople label and picker
        if self.imageView.image != nil {
          self.numOfPeopleLabel.isHidden = true
          self.numOfPeoplePicker.isHidden = true
          self.counterNoP.text = "Number of People: \(self.numOfPeople)"
        }
      }
    }
  }

  private func transformMatrix() -> CGAffineTransform {
    guard let image = imageView.image else { return CGAffineTransform() }
    let imageViewWidth = imageView.frame.size.width
    let imageViewHeight = imageView.frame.size.height
    let imageWidth = image.size.width
    let imageHeight = image.size.height

    let imageViewAspectRatio = imageViewWidth / imageViewHeight
    let imageAspectRatio = imageWidth / imageHeight
    let scale = (imageViewAspectRatio > imageAspectRatio) ?
      imageViewHeight / imageHeight :
      imageViewWidth / imageWidth

    // Image view's `contentMode` is `scaleAspectFit`, which scales the image to fit the size of the
    // image view by maintaining the aspect ratio. Multiple by `scale` to get image's original size.
    let scaledImageWidth = imageWidth * scale
    let scaledImageHeight = imageHeight * scale
    let xValue = (imageViewWidth - scaledImageWidth) / CGFloat(2.0)
    let yValue = (imageViewHeight - scaledImageHeight) / CGFloat(2.0)

    var transform = CGAffineTransform.identity.translatedBy(x: xValue, y: yValue)
    transform = transform.scaledBy(x: scale, y: scale)
    return transform
  }

  private func pointFrom(_ visionPoint: VisionPoint) -> CGPoint {
    return CGPoint(x: CGFloat(visionPoint.x.floatValue), y: CGFloat(visionPoint.y.floatValue))
  }

  private func process(_ visionImage: VisionImage, with textRecognizer: VisionTextRecognizer?) {
    // this is executed when detect is clicked
    // things to be done after detect is clicked
    //     - make dots for the number of people
    //     - start draggable session and make uilabels draggable
    //     - hide everything except photo and labels
    textRecognizer?.process(visionImage) { text, error in
      guard error == nil, let text = text else {
        let errorString = error?.localizedDescription ?? Constants.detectionNoResultsMessage
        self.resultsText = "Text recognizer failed with error: \(errorString)"
        // self.showResults()
        return
      }
      self.photoToolbar.isHidden = true
      self.detectToolbar.isHidden = true
      self.counterNoP.isHidden = true
        
      // Blocks.
      for block in text.blocks {
        print("block of text below:\n", block.text)

        // Lines.
        for line in block.lines {
          let transformedRect = line.frame.applying(self.transformMatrix())
          UIUtilities.addRectangle(
            transformedRect,
            to: self.annotationOverlayView,
            color: UIColor.orange
          )
          let label = UILabel(frame: transformedRect)
          label.text = line.text
          label.adjustsFontSizeToFitWidth = true
          label.isUserInteractionEnabled = true
          label.backgroundColor = UIColor(hue: 0.0806, saturation: 0.53, brightness: 0.96, alpha: 0.5)
          self.annotationOverlayView.addSubview(label)
        }
      }
      self.resultsText += "\(text.text)\n"
      // self.showResults()
    }
  }

  private func registerAutoMLModelsIfNeeded() {
    if areAutoMLModelsRegistered {
      return
    }

    let initialConditions = ModelDownloadConditions()
    let updateConditions = ModelDownloadConditions(
      allowsCellularAccess: false,
      allowsBackgroundDownloading: true
    )
    let remoteModel = RemoteModel(
      name: Constants.remoteAutoMLModelName,
      allowsModelUpdates: true,
      initialConditions: initialConditions,
      updateConditions: updateConditions
    )
    modelManager.register(remoteModel)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(remoteModelDownloadDidSucceed(_:)),
      name: .firebaseMLModelDownloadDidSucceed,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(remoteModelDownloadDidFail(_:)),
      name: .firebaseMLModelDownloadDidFail,
      object: nil
    )
    downloadProgressView.isHidden = false
    downloadProgressView.observedProgress = modelManager.download(remoteModel)

    guard let localModelFilePath = Bundle.main.path(
      forResource: Constants.localModelManifestFileName,
      ofType: Constants.autoMLManifestFileType
      ) else {
        print("Failed to find AutoML local model manifest file.")
        return
    }
    let localModel = LocalModel(name: Constants.localAutoMLModelName, path: localModelFilePath)
    modelManager.register(localModel)
    areAutoMLModelsRegistered = true
  }

  // MARK: - Notifications

  @objc
  private func remoteModelDownloadDidSucceed(_ notification: Notification) {
    let notificationHandler = {
      self.downloadProgressView.isHidden = true
      guard let userInfo = notification.userInfo,
        let remoteModel =
        userInfo[ModelDownloadUserInfoKey.remoteModel.rawValue] as? RemoteModel
        else {
          self.resultsText += "firebaseMLModelDownloadDidSucceed notification posted without a RemoteModel instance."
          return
      }
      self.resultsText += "Successfully downloaded the remote model with name: \(remoteModel.name). The model is ready for detection."
    }
    if Thread.isMainThread { notificationHandler(); return }
    DispatchQueue.main.async { notificationHandler() }
  }

  @objc
  private func remoteModelDownloadDidFail(_ notification: Notification) {
    let notificationHandler = {
      self.downloadProgressView.isHidden = true
      guard let userInfo = notification.userInfo,
        let remoteModel =
        userInfo[ModelDownloadUserInfoKey.remoteModel.rawValue] as? RemoteModel,
        let error = userInfo[ModelDownloadUserInfoKey.error.rawValue] as? NSError
        else {
          self.resultsText += "firebaseMLModelDownloadDidFail notification posted without a RemoteModel instance or error."
          return
      }
      self.resultsText += "Failed to download the remote model with name: \(remoteModel.name), error: \(error)."
    }
    if Thread.isMainThread { notificationHandler(); return }
    DispatchQueue.main.async { notificationHandler() }
  }
}

extension ViewController: UIPickerViewDataSource, UIPickerViewDelegate {
    
  func numberOfComponents(in numOfPeoplePicker: UIPickerView) -> Int
  {
      return 1
  }
    
  func pickerView(_ numOfPeoplePicker: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String?
  {
      return String(numsOfPeople[row])
  }
    
  func pickerView(_ numOfPeoplePicker: UIPickerView, numberOfRowsInComponent component: Int) -> Int
  {
      return numsOfPeople.count
  }
    
  func pickerView(_ numOfPeoplePicker: UIPickerView, didSelectRow row: Int, inComponent component: Int)
  {
      numOfPeople = numsOfPeople[row]
  }
}

// MARK: - UIImagePickerControllerDelegate

extension ViewController: UIImagePickerControllerDelegate {

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
// Local variable inserted by Swift 4.2 migrator.
let info = convertFromUIImagePickerControllerInfoKeyDictionary(info)

    clearResults()
    if let pickedImage = info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.originalImage)] as? UIImage {
      updateImageView(with: pickedImage)
    }
    dismiss(animated: true)
  }
}

/// Extension of ViewController for On-Device and Cloud detection.
extension ViewController {

  // MARK: - Vision On-Device Detection

  /// Detects text on the specified image and draws a frame around the recognized text using the
  /// On-Device text recognizer.
  ///
  /// - Parameter image: The image.
  // ran in detect function
  func detectTextOnDevice(image: UIImage?) {
    guard let image = image else { return }

    // [START init_text]
    let onDeviceTextRecognizer = vision.onDeviceTextRecognizer()
    // [END init_text]

    // Define the metadata for the image.
    let imageMetadata = VisionImageMetadata()
    imageMetadata.orientation = UIUtilities.visionImageOrientation(from: image.imageOrientation)

    // Initialize a VisionImage object with the given UIImage.
    let visionImage = VisionImage(image: image)
    visionImage.metadata = imageMetadata

    self.resultsText += "Running On-Device Text Recognition...\n"
    // this will run and post the popup with resultsText pasted
    process(visionImage, with: onDeviceTextRecognizer)
  }
}

// MARK: - Enums

private enum Constants {
  static let modelExtension = "tflite"
  static let localModelName = "mobilenet"
  static let quantizedModelFilename = "mobilenet_quant_v1_224"

  static let detectionNoResultsMessage = "No results returned."
  static let failedToDetectObjectsMessage = "Failed to detect objects in image."
  static let sparseTextModelName = "Sparse"
  static let denseTextModelName = "Dense"

  static let localAutoMLModelName = "local_automl_model"
  static let remoteAutoMLModelName = "remote_automl_model"
  static let localModelManifestFileName = "automl_labeler_manifest"
  static let autoMLManifestFileType = "json"

  static let labelConfidenceThreshold: Float = 0.75
  static let smallDotRadius: CGFloat = 5.0
  static let largeDotRadius: CGFloat = 10.0
  static let lineColor = UIColor.yellow.cgColor
  static let fillColor = UIColor.clear.cgColor
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKeyDictionary(_ input: [UIImagePickerController.InfoKey: Any]) -> [String: Any] {
	return Dictionary(uniqueKeysWithValues: input.map {key, value in (key.rawValue, value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKey(_ input: UIImagePickerController.InfoKey) -> String {
	return input.rawValue
}
