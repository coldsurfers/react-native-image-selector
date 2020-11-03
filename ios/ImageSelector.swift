import AVKit
import Photos
import PhotosUI

class EventEmitter {

    /// Shared Instance.
    public static var sharedInstance = EventEmitter()

    // ReactNativeEventEmitter is instantiated by React Native with the bridge.
    private static var eventEmitter: RCTEventEmitter!

    private init() {}

    // When React Native instantiates the emitter it is registered here.
    func registerEventEmitter(eventEmitter: RCTEventEmitter) {
        EventEmitter.eventEmitter = eventEmitter
    }

    func dispatch(name: String, body: Any?) {
        EventEmitter.eventEmitter.sendEvent(withName: name, body: body)
    }

    /// All Events which must be support by React Native.
    lazy var allEvents: [String] = {
        var allEventNames: [String] = ["DidSelectItem"]

        // Append all events here
        
        return allEventNames
    }()

}

@objc(ImageSelector)
class ImageSelector: RCTEventEmitter, UINavigationControllerDelegate {
    
    let imagePickerController: UIImagePickerController = UIImagePickerController()
    
    private var fetchedAssets: PHFetchResult<PHAsset> = PHFetchResult<PHAsset>()
    private var globalCallback: RCTResponseSenderBlock?
    private var imageShowerViewController: ImageShowerViewController?
    
    override init() {
        super.init()
        EventEmitter.sharedInstance.registerEventEmitter(eventEmitter: self)
    }
    
    override func supportedEvents() -> [String]! {
        return EventEmitter.sharedInstance.allEvents
    }
    
    func requestCameraAuthorization() -> Void {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] (isAuthorized: Bool) in
            guard let `self` = self else { return }
            guard let callback = self.globalCallback else { return }
            if isAuthorized {
                self.launchCamera()
            } else {
                let error = ["error": "CAMERA_PERMISSION_DENIED"]
                callback([
                    error
                ])
            }
        }
    }
    
    func requestLibraryAuthorization() -> Void {
        PHPhotoLibrary.requestAuthorization { [weak self] (status: PHAuthorizationStatus) in
            guard let `self` = self else { return }
            guard let callback = self.globalCallback else { return }
            switch status {
                case .authorized:
                    self.launchLibrary()
                    break
                default:
                    let error = ["error": "LIBRARY_PERMISSION_DENIED"]
                    callback([
                        error
                    ])
                    break
            }
        }
    }
    
    func checkCameraPermission() -> Void {
        guard let callback = self.globalCallback else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
            case .authorized:
                self.launchCamera()
                break
            case .notDetermined:
                self.requestCameraAuthorization()
                break
            default:
                let error = ["error": "CAMERA_PERMISSION_DENIED"]
                callback([
                    error
                ])
                break
        }
    }
    
    func checkLibraryPermission() -> Void {
        guard let callback = self.globalCallback else { return }
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
            case .authorized:
                self.launchLibrary()
                break
            case .notDetermined:
                self.requestLibraryAuthorization()
                break
            default:
                let error = ["error": "LIBRARY_PERMISSION_DENIED"]
                callback([
                    error
                ])
                break
        }
    }
    
    func launchLibrary() -> Void {
        guard let callback = self.globalCallback else { return }
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeAssetSourceTypes = .typeUserLibrary
        self.fetchedAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        self.imageShowerViewController = ImageShowerViewController(fetchedAssets: self.fetchedAssets, callback: callback)
        guard let imageShowerViewController = self.imageShowerViewController else { return }
        PHPhotoLibrary.shared().register(self)
        DispatchQueue.main.async {
            guard let rootViewController = RCTPresentedViewController() else { return }
            let navigationController = UINavigationController(rootViewController: imageShowerViewController)
            navigationController.modalPresentationStyle = .overFullScreen
            rootViewController.present(navigationController, animated: true, completion: nil)
        }
    }
    
    func launchCamera() -> Void {
        self.imagePickerController.delegate = self
        self.imagePickerController.sourceType = .camera
        DispatchQueue.main.async {
            guard let rootViewController = RCTPresentedViewController() else { return }
            rootViewController.present(self.imagePickerController, animated: true) {
                
            }
        }
    }
    
    @objc
    func launchPicker(_ callback: @escaping RCTResponseSenderBlock) -> Void {
        self.globalCallback = callback
        let alert = UIAlertController(title: "사진 선택", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "사진 촬영", style: .default, handler: { [weak self] (_: UIAlertAction) in
            guard let `self` = self else { return }
            #if targetEnvironment(simulator)
                callback([
                    ["error": "SIMULATOR_ERROR"]
                ])
            #else
                self.checkCameraPermission()
            #endif
        }))
        alert.addAction(UIAlertAction(title: "앨범에서 가져오기", style: .default, handler: { [weak self] (_: UIAlertAction) in
            guard let `self` = self else { return }
            self.checkLibraryPermission()
        }))
        alert.addAction(UIAlertAction(title: "취소", style: .cancel, handler: { (_: UIAlertAction) in
            
        }))
        DispatchQueue.main.async {
            guard let rootViewController = RCTPresentedViewController() else { return }
            rootViewController.present(alert, animated: true) {
                
            }
        }
    }
    
    func createCacheFile(imageData: Data) -> [String: Any] {
        let fileName: String = "react-native-image-selector_\(UUID().uuidString).png"
        let paths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        let path = paths.first ?? ""
        let filePath = "\(path)/\(fileName)"
        if !FileManager.default.fileExists(atPath: filePath) {
            FileManager.default.createFile(atPath: filePath, contents: imageData, attributes: nil)
        }
        return ["filePath": filePath, "fileName": fileName]
    }
}


extension ImageSelector: UIImagePickerControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        guard let callback = self.globalCallback else { return }
        picker.dismiss(animated: true) {
            callback([
                ["error": "USER_CANCEL"]
            ])
        }
    }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let callback = self.globalCallback else { return }
        var response: [String: Any] = [:]
        switch picker.sourceType {
            case .camera:
                if let pickedImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                    if let imageData = pickedImage.pngData() {
                        let fileCreateResult = self.createCacheFile(imageData: imageData)
                        response["uri"] = "file://\(fileCreateResult["filePath"] ?? "")"
                        response["fileName"] = "\(fileCreateResult["fileName"] ?? "")"
                        response["type"] = "png"
                        response["fileSize"] = imageData.count
                    }
                }
                callback([
                    nil,
                    response
                ])
                break
            case .photoLibrary, .savedPhotosAlbum:
                if let referenceURL = info[UIImagePickerController.InfoKey.referenceURL] as? URL {
                    response["uri"] = referenceURL.absoluteString
                    response["type"] = (referenceURL.absoluteString as NSString).pathExtension
                    let asset = PHAsset.fetchAssets(withALAssetURLs: [referenceURL], options: nil)
                    if let fileName = asset.firstObject?.value(forKey: "filename") {
                        response["fileName"] = fileName
                    }
                }
                if let pickedImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                    if let imageData = pickedImage.pngData() {
                        response["fileSize"] = imageData.count
                    }
                }
                callback([
                    nil,
                    response
                ])
                break
            default:
                callback([
                    ["error": "SOURCE_TYPE_MISMATCH"]
                ])
                break
        }
        picker.dismiss(animated: true, completion: nil)
    }
}

extension ImageSelector: PHPickerViewControllerDelegate {
    @available(iOS 14, *)
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
    }
}

extension ImageSelector: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        if let changedDetails = changeInstance.changeDetails(for: self.fetchedAssets) {
            guard let imageShowerViewController = self.imageShowerViewController else { return }
            let newFetchedAssets = changedDetails.fetchResultAfterChanges
            imageShowerViewController.fetchedAssets = newFetchedAssets
            DispatchQueue.main.async {
                imageShowerViewController.collectionView.reloadData()
            }
        }
    }
}

class ImageShowerViewController: UIViewController {
    public var fetchedAssets: PHFetchResult<PHAsset>?
    public lazy var collectionView: UICollectionView = {
        self.layout.scrollDirection = .vertical
        let cv = UICollectionView(frame: .zero, collectionViewLayout: self.layout)
        cv.register(ImageShowerCell.self, forCellWithReuseIdentifier: self.reusableIdentifier)
        cv.backgroundColor = .white
        cv.delegate = self
        cv.dataSource = self
        return cv
    }()
    private var globalCallback: RCTResponseSenderBlock?
    private let layout = UICollectionViewFlowLayout()
    private let reusableIdentifier: String = "cell"
    
    init(fetchedAssets: PHFetchResult<PHAsset>, callback: @escaping RCTResponseSenderBlock) {
        super.init(nibName: nil, bundle: nil)
        self.fetchedAssets = fetchedAssets
        self.globalCallback = callback
        self.title = "모든 사진"
        let cancelBarButtonItem: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.dismissViewController(_:)))
        self.navigationItem.rightBarButtonItem = cancelBarButtonItem
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .white
        self.view.addSubview(self.collectionView)
        self.collectionView.translatesAutoresizingMaskIntoConstraints = false
        let topAnchor = self.collectionView.topAnchor.constraint(equalTo: self.view.topAnchor)
        let leftAnchor = self.collectionView.leftAnchor.constraint(equalTo: self.view.leftAnchor)
        let bottomAnchor = self.collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        let rightAnchor = self.collectionView.rightAnchor.constraint(equalTo: self.view.rightAnchor)
        self.view.addConstraints([topAnchor, leftAnchor, bottomAnchor, rightAnchor])
    }
    
    @objc
    func dismissViewController(_ sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }
}

class ImageShowerCell: UICollectionViewCell {
    let cellImageView: UIImageView = {
        let imageView = UIImageView(frame: .zero)
        return imageView
    }()
    var asset: PHAsset? = nil {
        didSet (oldAsset) {
            if let newAsset = asset {
                self.fetchImage(asset: newAsset)
            }
        }
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.backgroundColor = .groupTableViewBackground
        self.contentView.addSubview(self.cellImageView)
        self.cellImageView.translatesAutoresizingMaskIntoConstraints = false
        let topAnchor = self.cellImageView.topAnchor.constraint(equalTo: self.contentView.topAnchor)
        let leftAnchor = self.cellImageView.leftAnchor.constraint(equalTo: self.contentView.leftAnchor)
        let bottomAnchor = self.cellImageView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor)
        let rightAnchor = self.cellImageView.rightAnchor.constraint(equalTo: self.contentView.rightAnchor)
        self.contentView.addConstraints([topAnchor, leftAnchor, bottomAnchor, rightAnchor])
    }

    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        self.cellImageView.image = nil
    }
    
    func fetchImage(asset: PHAsset) -> Void {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
//        manager.requestImageData(for: asset, options: options) { (data: Data?, _: String?, _: UIImage.Orientation, _: [AnyHashable : Any]?) in
//            if let data = data {
//                self.cellImageView.image = UIImage(data: data)
//            }
//        }
        manager.requestImage(for: asset, targetSize: CGSize(width: self.contentView.layer.frame.width, height: self.contentView.layer.frame.height), contentMode: .aspectFit, options: options) { (image: UIImage?, info: [AnyHashable : Any]?) in
            self.cellImageView.image = image
        }
    }
}

extension ImageShowerViewController: UICollectionViewDelegateFlowLayout, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let assets = self.fetchedAssets else { return 0 }
        return assets.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: self.reusableIdentifier, for: indexPath) as? ImageShowerCell else { return UICollectionViewCell() }
        guard let assets = self.fetchedAssets else { return cell }
        let asset = assets.object(at: indexPath.item)
        cell.asset = asset
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: collectionView.layer.frame.width / 3 - 2, height: collectionView.layer.frame.height / 6.5)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 2
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 4
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let assets = self.fetchedAssets else { return }
        let asset = assets.object(at: indexPath.item)
        var response: [String: Any] = [:]
        if let assetResource = PHAssetResource.assetResources(for: asset).first {
            let fileName = assetResource.originalFilename
            response["fileName"] = fileName
            let type = (fileName as NSString).pathExtension
            response["type"] = type
            if let fileSize = assetResource.value(forKey: "fileSize") as? Float {
                response["fileSize"] = fileSize
            }
            asset.requestContentEditingInput(with: nil) { [weak self] (assetInput: PHContentEditingInput?, _: [AnyHashable : Any]) in
                guard let `self` = self else { return }
                if let absoluteURI = assetInput?.fullSizeImageURL?.absoluteString {
                    response["uri"] = absoluteURI
                    guard let callback = self.globalCallback else { return }
                    self.dismiss(animated: true) {
                        callback([
                            nil,
                            response
                        ])
                    }
                }
            }
        }
    }
}

