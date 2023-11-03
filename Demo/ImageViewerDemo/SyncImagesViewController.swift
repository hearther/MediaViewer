//
//  SyncImagesViewController.swift
//  ImageViewerDemo
//
//  Created by Yusaku Nishi on 2023/03/05.
//

import UIKit
import MediaViewer

final class SyncImagesViewController: UIViewController {
    
    private typealias CellRegistration = UICollectionView.CellRegistration<
        ImageCell,
        (image: UIImage, contentMode: UIView.ContentMode)
    >
    
    private let imageGridView = ImageGridView()
    
    private let cellRegistration = CellRegistration { cell, _, item in
        cell.configure(with: item.image, contentMode: item.contentMode)
    }
    
    private lazy var dataSource = UICollectionViewDiffableDataSource<Int, UIImage>(
        collectionView: imageGridView.collectionView
    ) { [weak self] collectionView, indexPath, image in
        guard let self else { return nil }
        return collectionView.dequeueConfiguredReusableCell(
            using: self.cellRegistration,
            for: indexPath,
            item: (image: image, contentMode: .scaleAspectFill)
        )
    }
    
    // MARK: - Lifecycle
    
    override func loadView() {
        imageGridView.collectionView.delegate = self
        view = imageGridView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpViews()
    }
    
    private func setUpViews() {
        // Navigation
        navigationItem.title = "Sync Sample"
        navigationItem.backButtonDisplayMode = .minimal
        
        // Subviews
        var snapshot = dataSource.snapshot()
        snapshot.appendSections([0])
        snapshot.appendItems((0...20).map { UIImage(systemName: "\($0).circle")! })
        dataSource.apply(snapshot)
    }
}

// MARK: - UICollectionViewDelegate -

extension SyncImagesViewController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let mediaViewer = MediaViewerViewController(page: indexPath.item, dataSource: self)
        navigationController?.delegate = mediaViewer
        navigationController?.pushViewController(mediaViewer, animated: true)
    }
}

// MARK: - MediaViewerDataSource -

extension SyncImagesViewController: MediaViewerDataSource {
    
    func numberOfMedia(in mediaViewer: MediaViewerViewController) -> Int {
        dataSource.snapshot().numberOfItems
    }
    
    func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        imageSourceOnPage page: Int
    ) -> ImageSource {
        .sync(dataSource.snapshot().itemIdentifiers[page])
    }
    
    func transitionSourceView(
        forCurrentPageOf mediaViewer: MediaViewerViewController
    ) -> UIImageView? {
        let currentPage = mediaViewer.currentPage
        let indexPathForCurrentImage = IndexPath(item: currentPage, section: 0)
        
        // NOTE: Without this, later cellForItem(at:) sometimes returns nil.
        imageGridView.collectionView.layoutIfNeeded()
        
        guard let cellForCurrentImage = imageGridView.collectionView.cellForItem(at: indexPathForCurrentImage) as? ImageCell else {
            return nil
        }
        return cellForCurrentImage.imageView
    }
}
