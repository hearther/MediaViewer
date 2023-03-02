//
//  ImageViewerViewController.swift
//  
//
//  Created by Yusaku Nishi on 2023/02/25.
//

import UIKit
import Combine

/// The way to animate the image transition.
public enum ImageTransition: Hashable, Sendable {
    
    /// The fade animation with the specified duration.
    case fade(duration: TimeInterval)
    
    /// No animation.
    case none
}

/// The image source for the image viewer.
public enum ImageSource {
    
    /// An image that can be acquired synchronously.
    case sync(UIImage?)
    
    /// An image that can be acquired asynchronously.
    ///
    /// The viewer will use `provider` to acquire an image and display it using `transition`.
    case async(transition: ImageTransition = .fade(duration: 0.2),
               provider: () async -> UIImage?)
}

// MARK: - ImageViewerDataSource -

/// The object you use to provide data for an image viewer.
public protocol ImageViewerDataSource: AnyObject {
    
    /// Asks the data source to return the number of images in the image viewer.
    /// - Parameter imageViewer: An object representing the image viewer requesting this information.
    /// - Returns: The number of images in `imageViewer`.
    func numberOfImages(in imageViewer: ImageViewerViewController) -> Int
    
    /// Asks the data source to return an image to view at the particular page in the image viewer.
    /// - Parameters:
    ///   - imageViewer: An object representing the image viewer requesting this information.
    ///   - page: A page in the image viewer.
    /// - Returns: An image to view at the particular page in `imageViewer`.
    func imageViewer(_ imageViewer: ImageViewerViewController,
                     imageAtPage page: Int) async -> UIImage?
    
    /// Asks the data source to return the thumbnail view for the current page of the image viewer.
    ///
    /// The image viewer uses this thumbnail view for push or pop transitions.
    /// On the push transition, an animation runs as the image expands from this thumbnail view. The reverse happens on the pop.
    ///
    /// If `nil`, the default animation runs on the transition.
    ///
    /// - Parameter imageViewer: An object representing the image viewer requesting this information.
    /// - Returns: The thumbnail view for current page of `imageViewer`.
    func thumbnailView(forCurrentPageOf imageViewer: ImageViewerViewController) -> UIImageView?
}

// MARK: - ImageViewerViewController -

/// An image viewer.
///
/// It is recommended to set your `ImageViewerViewController` instance to `navigationController?.delegate` to enable smooth transition animation.
/// ```swift
/// let imageViewer = ImageViewerViewController(image: imageToView)
/// imageViewer.imageViewerDataSource = self
/// navigationController?.delegate = imageViewer
/// navigationController?.pushViewController(imageViewer, animated: true)
/// ```
///
/// - Note: `ImageViewerViewController` must be used in `UINavigationController`. It is NOT allowed to change `dataSource` and `delegate` properties of ``UIPageViewController``.
open class ImageViewerViewController: UIPageViewController {
    
    private var cancellables: Set<AnyCancellable> = []
    
    /// The data source of the image viewer object.
    open weak var imageViewerDataSource: (any ImageViewerDataSource)?
    
    /// The current page of the image viewer.
    public var currentPage: Int {
        currentPageViewController.page
    }
    
    var currentPageViewController: ImageViewerOnePageViewController {
        guard let imageViewerOnePage = viewControllers?.first as? ImageViewerOnePageViewController else {
            preconditionFailure("\(Self.self) must have only one \(ImageViewerOnePageViewController.self).")
        }
        return imageViewerOnePage
    }
    
    private let imageViewerVM = ImageViewerViewModel()
    
    private let singleTapRecognizer = UITapGestureRecognizer()
    
    private let panRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }()
    
    private var interactivePopTransition: ImageViewerInteractivePopTransition?
    
    // MARK: Backups
    
    private var navigationBarScrollEdgeAppearanceBackup: UINavigationBarAppearance?
    private var navigationBarHiddenBackup = false
    
    // MARK: - Initializers
    
    /// Creates a new viewer.
    /// - Parameters:
    ///   - page: The page number of the image.
    ///   - dataSource: The data source for the viewer.
    public init(page: Int, dataSource: any ImageViewerDataSource) {
        super.init(transitionStyle: .scroll,
                   navigationOrientation: .horizontal,
                   options: [
                    .interPageSpacing: 40,
                    .spineLocation: SpineLocation.none.rawValue
                   ])
        imageViewerDataSource = dataSource
        
        guard let imageViewerPage = makeImageViewerPage(forPage: page) else {
            preconditionFailure("Page \(page) out of range.")
        }
        setViewControllers([imageViewerPage], direction: .forward, animated: false)
    }
    
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // MARK: - Lifecycle
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        dataSource = self
        delegate = self
        
        guard let navigationController else {
            preconditionFailure("\(Self.self) must be embedded in UINavigationController.")
        }
        
        navigationBarScrollEdgeAppearanceBackup = navigationController.navigationBar.scrollEdgeAppearance
        navigationBarHiddenBackup = navigationController.isNavigationBarHidden
        
        setUpGestureRecognizers()
        setUpSubscriptions()
    }
    
    private func setUpGestureRecognizers() {
        singleTapRecognizer.addTarget(self, action: #selector(backgroundTapped))
        view.addGestureRecognizer(singleTapRecognizer)
        
        panRecognizer.delegate = self
        panRecognizer.addTarget(self, action: #selector(panned))
        view.addGestureRecognizer(panRecognizer)
    }
    
    private func setUpSubscriptions() {
        imageViewerVM.$showsImageOnly
            .sink { [weak self] showsImageOnly in
                guard let self else { return }
                let animator = UIViewPropertyAnimator(duration: UINavigationController.hideShowBarDuration,
                                                      dampingRatio: 1) {
                    self.navigationController?.navigationBar.alpha = showsImageOnly ? 0 : 1
                    self.view.backgroundColor = showsImageOnly ? .black : .systemBackground
                }
                if showsImageOnly {
                    animator.addCompletion { position in
                        if position == .end {
                            self.navigationController?.isNavigationBarHidden = true
                        }
                    }
                } else {
                    self.navigationController?.isNavigationBarHidden = false
                }
                animator.startAnimation()
            }
            .store(in: &cancellables)
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        navigationController?.navigationBar.scrollEdgeAppearance = navigationBarScrollEdgeAppearanceBackup
        navigationController?.setNavigationBarHidden(navigationBarHiddenBackup, animated: animated)
    }
    
    // MARK: - Override
    
    open override var prefersStatusBarHidden: Bool {
        true
    }
    
    open override func setViewControllers(_ viewControllers: [UIViewController]?,
                                          direction: UIPageViewController.NavigationDirection,
                                          animated: Bool,
                                          completion: ((Bool) -> Void)? = nil) {
        super.setViewControllers(viewControllers,
                                 direction: direction,
                                 animated: animated,
                                 completion: completion)
        pageDidChange()
    }
    
    // MARK: - Methods
    
    private func pageDidChange() {
        singleTapRecognizer.require(toFail: currentPageViewController.imageDoubleTapRecognizer)
    }
    
    // MARK: - Actions
    
    @objc
    private func backgroundTapped(recognizer: UITapGestureRecognizer) {
        imageViewerVM.showsImageOnly.toggle()
    }
    
    @objc
    private func panned(recognizer: UIPanGestureRecognizer) {
        // Check whether to transition interactively
        guard let sourceThumbnailView = imageViewerDataSource?.thumbnailView(forCurrentPageOf: self) else { return }
        
        if recognizer.state == .began {
            // Start the interactive pop transition
            interactivePopTransition = .init(sourceThumbnailView: sourceThumbnailView)
            navigationController?.popViewController(animated: true)
        }
        
        interactivePopTransition?.panRecognized(by: recognizer, in: self)
        
        switch recognizer.state {
        case .possible, .began, .changed:
            break
        case .ended, .cancelled, .failed:
            interactivePopTransition = nil
        @unknown default:
            assertionFailure("Unknown state: \(recognizer.state)")
            interactivePopTransition = nil
        }
    }
}

// MARK: - ImageViewerOnePageViewControllerDelegate -

extension ImageViewerViewController: ImageViewerOnePageViewControllerDelegate {
    
    func imageViewerPage(_ imageViewerPage: ImageViewerOnePageViewController,
                         didDoubleTap imageView: UIImageView) {
        imageViewerVM.showsImageOnly = true
    }
}

// MARK: - UIPageViewControllerDataSource -

extension ImageViewerViewController: UIPageViewControllerDataSource {
    
    open func presentationCount(for pageViewController: UIPageViewController) -> Int {
        imageViewerDataSource?.numberOfImages(in: self) ?? 0
    }
    
    open func pageViewController(_ pageViewController: UIPageViewController,
                                 viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let imageViewerPageVC = viewController as? ImageViewerOnePageViewController else {
            assertionFailure("Unknown view controller: \(viewController)")
            return nil
        }
        let previousPage = imageViewerPageVC.page - 1
        if let previousPageVC = makeImageViewerPage(forPage: previousPage) {
            return previousPageVC
        }
        return nil
    }
    
    open func pageViewController(_ pageViewController: UIPageViewController,
                                 viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let imageViewerPageVC = viewController as? ImageViewerOnePageViewController else {
            assertionFailure("Unknown view controller: \(viewController)")
            return nil
        }
        let nextPage = imageViewerPageVC.page + 1
        if let nextPageVC = makeImageViewerPage(forPage: nextPage) {
            return nextPageVC
        }
        return nil
    }
    
    private func makeImageViewerPage(forPage page: Int) -> ImageViewerOnePageViewController? {
        guard let imageViewerDataSource,
              0 <= page,
              page < imageViewerDataSource.numberOfImages(in: self) else { return nil }
        let imageViewerPage = ImageViewerOnePageViewController(page: page)
        imageViewerPage.delegate = self
        Task {
            let image = await imageViewerDataSource.imageViewer(self, imageAtPage: page)
            imageViewerPage.imageViewerOnePageView.setImage(image, with: .fade(duration: 0.2))
        }
        return imageViewerPage
    }
}

// MARK: - UIPageViewControllerDelegate -

extension ImageViewerViewController: UIPageViewControllerDelegate {
    
    open func pageViewController(_ pageViewController: UIPageViewController,
                                 didFinishAnimating finished: Bool,
                                 previousViewControllers: [UIViewController],
                                 transitionCompleted completed: Bool) {
        if completed {
            pageDidChange()
        }
    }
}

// MARK: - UINavigationControllerDelegate -

extension ImageViewerViewController: UINavigationControllerDelegate {
    
    public func navigationController(_ navigationController: UINavigationController,
                                     animationControllerFor operation: UINavigationController.Operation,
                                     from fromVC: UIViewController,
                                     to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        guard let sourceThumbnailView = imageViewerDataSource?.thumbnailView(forCurrentPageOf: self) else { return nil }
        return ImageViewerTransition(operation: operation, sourceThumbnailView: sourceThumbnailView)
    }
    
    public func navigationController(_ navigationController: UINavigationController,
                                     interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? {
        return interactivePopTransition
    }
}

// MARK: - UIGestureRecognizerDelegate -

extension ImageViewerViewController: UIGestureRecognizerDelegate {
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Tune gesture recognizers to make it easier to start an interactive pop.
        guard gestureRecognizer == panRecognizer else { return false }
        let velocity = panRecognizer.velocity(in: nil)
        let isMovingDown = velocity.y > 0 && velocity.y > abs(velocity.x)
        
        let imageScrollView = currentPageViewController.imageViewerOnePageView.scrollView
        switch otherGestureRecognizer {
        case imageScrollView.panGestureRecognizer:
            // If the scroll position reaches the top edge, allow an interactive pop by pulldown.
            let isReachingTopEdge = imageScrollView.contentOffset.y <= 0
            if isReachingTopEdge && isMovingDown {
                // Cancel scrolling
                imageScrollView.panGestureRecognizer.state = .cancelled
                return true
            }
        case let pagingRecognizer as UIPanGestureRecognizer where pagingRecognizer.view is UIScrollView:
            assert(pagingRecognizer.view?.superview == view,
                   "Unknown pan gesture recognizer: \(otherGestureRecognizer)")
            // Prefer an interactive pop over paging.
            if isMovingDown {
                // Cancel paging
                pagingRecognizer.state = .cancelled
                return true
            }
        default:
            break
        }
        return false
    }
}
