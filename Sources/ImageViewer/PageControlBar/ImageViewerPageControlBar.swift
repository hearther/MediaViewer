//
//  ImageViewerPageControlBar.swift
//  
//
//  Created by Yusaku Nishi on 2023/03/18.
//

import UIKit

protocol ImageViewerPageControlBarDataSource: AnyObject {
    func imageViewerPageControlBar(_ pageControlBar: ImageViewerPageControlBar,
                                   thumbnailOnPage page: Int,
                                   filling preferredThumbnailSize: CGSize) -> ImageSource
}

protocol ImageViewerPageControlBarDelegate: AnyObject {
    func imageViewerPageControlBar(_ pageControlBar: ImageViewerPageControlBar,
                                   didVisitThumbnailOnPage page: Int)
}

final class ImageViewerPageControlBar: UIView {
    
    weak var dataSource: (any ImageViewerPageControlBarDataSource)?
    weak var delegate: (any ImageViewerPageControlBarDelegate)?
    
    private let layout = ImageViewerPageControlBarLayout()
    
    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.showsHorizontalScrollIndicator = false
        return collectionView
    }()
    
    lazy var diffableDataSource = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) { [weak self] collectionView, indexPath, page in
        guard let self else { return nil }
        return collectionView.dequeueConfiguredReusableCell(using: self.cellRegistration,
                                                            for: indexPath,
                                                            item: page)
    }
    
    private lazy var cellRegistration = UICollectionView.CellRegistration<PageControlBarThumbnailCell, Int> { [weak self] cell, indexPath, page in
        guard let self, let dataSource = self.dataSource else { return }
        let scale = self.window?.screen.scale ?? 3
        let preferredSize = CGSize(width: cell.bounds.width * scale,
                                   height: cell.bounds.height * scale)
        let thumbnailSource = dataSource.imageViewerPageControlBar(
            self,
            thumbnailOnPage: page,
            filling: preferredSize
        )
        cell.configure(with: thumbnailSource)
    }
    
    private var shouldDetectScrolling = true
    
    // MARK: - Initializers
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViews()
    }
    
    private func setUpViews() {
        // FIXME: [Workaround] Initialize cellRegistration before applying a snapshot to diffableDataSource.
        _ = cellRegistration
        
        // Subviews
        collectionView.delegate = self
        addSubview(collectionView)
        
        // Layout
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    // MARK: - Override
    
    override var intrinsicContentSize: CGSize {
        CGSize(width: super.intrinsicContentSize.width,
               height: 42)
    }
    
    // MARK: - Methods
    
    func configure(numberOfPages: Int, currentPage: Int) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(0 ..< numberOfPages))
        
        // Ignore scrolling until setup is complete
        shouldDetectScrolling = false
        diffableDataSource.apply(snapshot) {
            self.scroll(toPage: currentPage, animated: false)
            self.shouldDetectScrolling = true
        }
    }
    
    func scroll(toPage page: Int, animated: Bool) {
        let indexPath = IndexPath(item: page, section: 0)
        collectionView.scrollToItem(at: indexPath,
                                    at: .centeredHorizontally,
                                    animated: animated)
    }
}

// MARK: - UICollectionViewDelegate -

extension ImageViewerPageControlBar: UICollectionViewDelegate {
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard shouldDetectScrolling else { return }
        let offsetX = collectionView.contentOffset.x
        let center = CGPoint(x: offsetX + collectionView.bounds.width / 2, y: 0)
        if let indexPathForCenterItem = collectionView.indexPathForItem(at: center),
           layout.indexPathForExpandingItem != indexPathForCenterItem {
            delegate?.imageViewerPageControlBar(self, didVisitThumbnailOnPage: indexPathForCenterItem.item)
        }
    }
}
