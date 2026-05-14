//
//  PinnedHeaderWithPagesViewController.swift
//
//  Created by Ulises Giacoman on 9/9/25.
//

import UIKit

/// Combines a collapsing header, a sticky tab bar, and horizontally-paged content in a single view controller.
/// Uses a container/overlay dual-scroll-view pattern so the header collapses as the user scrolls,
/// then the active page's content scrolls independently.
class PinnedHeaderWithPagesViewController: UIViewController, UIScrollViewDelegate, SwiftUIViewReadinessProtocol {
    /// Contains the header and pages stacked vertically.
    private var containerScrollView: UIScrollView!

    /// Handles content offsets and scrolling logic; sits on top and captures all pan gestures.
    private var overlayScrollView: UIScrollView!

    /// Scroll/pan views for each page, keyed by page index.
    private var panViews: [Int: UIView] = [:] {
        didSet {
            if let scrollView = panViews[currentIndex] as? UIScrollView {
                scrollView.panGestureRecognizer.require(toFail: overlayScrollView.panGestureRecognizer)
                scrollView.contentInsetAdjustmentBehavior = .never
                scrollView.addObserver(self, forKeyPath: #keyPath(UIScrollView.contentSize), options: .new, context: nil)
                scrollView.addObserver(self, forKeyPath: #keyPath(UIScrollView.contentOffset), options: .new, context: nil)
            }
        }
    }

    private var currentIndex: Int = 0

    private var pagerTabHeight: CGFloat {
        bottomVC.pagerTabHeight ?? 40
    }

    weak var dataSource: PinnedHeaderDataSource!
    weak var delegate: PinnedHeaderDelegate?

    private var headerView: UIView! {
        headerVC.view
    }

    private var bottomView: UIView! {
        bottomVC.view
    }

    private var headerVC: UIViewController!
    private var bottomVC: (UIViewController & PagerAwareProtocol)!

    /// Content offset cache per page, so switching tabs restores the previous scroll position.
    private var contentOffsets: [Int: CGFloat] = [:]
    private var panOffsets: [Int: CGFloat] = [:]

    /// Saves the bottom scroll offset when pushing a new view controller so it can be
    /// restored when popping back, preventing a visible jump.
    private var lastOffsetForBottomScrollBeforePush: CGPoint?

    deinit {
        self.removeObservers()
    }

    private func removeObservers() {
        for keyValuePair in self.panViews {
            let (_, view) = keyValuePair
            if let scrollView = view as? UIScrollView {
                scrollView.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentSize))
                scrollView.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentOffset))
            }
        }
    }

    override public func loadView() {
        containerScrollView = UIScrollView()
        containerScrollView.scrollsToTop = false
        containerScrollView.showsVerticalScrollIndicator = false

        overlayScrollView = UIScrollView()
        overlayScrollView.showsVerticalScrollIndicator = false
        overlayScrollView.backgroundColor = UIColor.clear

        let view = UIView()
        view.addSubview(overlayScrollView)
        view.addSubview(containerScrollView)
        self.view = view
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        overlayScrollView.delegate = self
        overlayScrollView.layer.zPosition = CGFloat.greatestFiniteMagnitude
        overlayScrollView.contentInsetAdjustmentBehavior = .never
        overlayScrollView.pinEdges(to: self.view)

        containerScrollView.addGestureRecognizer(overlayScrollView.panGestureRecognizer)
        containerScrollView.contentInsetAdjustmentBehavior = .never
        containerScrollView.pinEdges(to: self.view)

        headerVC = dataSource.headerViewController()
        Self.add(parent: self, to: headerVC, to: containerScrollView)
        headerView.constraint(to: containerScrollView, attribute: .leading, secondAttribute: .leading)
        headerView.constraint(to: containerScrollView, attribute: .trailing, secondAttribute: .trailing)
        headerView.constraint(to: containerScrollView, attribute: .top, secondAttribute: .top)
        headerView.constraint(to: containerScrollView, attribute: .width, secondAttribute: .width)

        bottomVC = dataSource.bottomViewController()
        bottomVC.pageDelegate = self
        Self.add(parent: self, to: bottomVC, to: containerScrollView)
        bottomView.constraint(to: containerScrollView, attribute: .leading, secondAttribute: .leading)
        bottomView.constraint(to: containerScrollView, attribute: .trailing, secondAttribute: .trailing)
        bottomView.constraint(to: containerScrollView, attribute: .bottom, secondAttribute: .bottom)
        bottomView.constraint(to: headerView, attribute: .top, secondAttribute: .bottom)
        bottomView.constraint(to: containerScrollView, attribute: .width, secondAttribute: .width)
        bottomView.constraint(to: containerScrollView,
                              attribute: .height,
                              secondAttribute: .height)

        setupInitialPanViewIfReady()
        delegate?.pinnedHeaderScrollViewDidLoad(overlayScrollView)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        lastOffsetForBottomScrollBeforePush = nil
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if panViews.count > currentIndex, let scroll = panViews[currentIndex] as? UIScrollView {
            lastOffsetForBottomScrollBeforePush = scroll.contentOffset
        }
    }

    private func updateOverlayScrollContentSize(with bottomView: UIView) {
        self.overlayScrollView.contentSize = getContentSize(for: bottomView)
    }

    @MainActor
    private func freezeBottomContentOffsetWhileNavigating(for bottomScrollView: UIScrollView) {
        guard let lastOffsetForBottomScrollBeforePush else { return }
        let isOffsetChanged = bottomScrollView.contentOffset != lastOffsetForBottomScrollBeforePush
        if isOffsetChanged {
            bottomScrollView.contentOffset = lastOffsetForBottomScrollBeforePush
        }
    }

    private func getContentSize(for bottomView: UIView) -> CGSize {
        if let scroll = bottomView as? UIScrollView {
            let bottomHeight = max(scroll.contentSize.height, self.view.frame.height - dataSource.minHeaderHeight() - pagerTabHeight - view.safeAreaInsets.bottom)
            return CGSize(width: scroll.contentSize.width,
                          height: bottomHeight + headerView.frame.height + pagerTabHeight + view.safeAreaInsets.bottom)
        } else {
            let bottomHeight = self.view.frame.height - dataSource.minHeaderHeight() - pagerTabHeight
            return CGSize(width: bottomView.frame.width,
                          height: bottomHeight + headerView.frame.height + pagerTabHeight + view.safeAreaInsets.bottom)
        }
    }

    private func setupInitialPanViewIfReady() {
        guard let vc = bottomVC.currentViewController else { return }

        if let hostingVC = vc as? SwiftUIHostingProtocol {
            hostingVC.setReadinessDelegate(self)
            return
        }

        let panView = vc.scrollView()
        panViews[currentIndex] = panView
        updateOverlayScrollContentSize(with: panView)
    }

    // MARK: SwiftUIViewReadinessProtocol

    func notifySwiftUIViewReady() {
        guard let vc = bottomVC.currentViewController else { return }
        let panView = vc.scrollView()
        panViews[currentIndex] = panView
        updateOverlayScrollContentSize(with: panView)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change _: [NSKeyValueChangeKey: Any]?, context _: UnsafeMutableRawPointer?) {
        guard let scrollView = object as? UIScrollView else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let index: Int? = panViews.first(where: { $0.value == scrollView })?.key

            if let index, let scroll = panViews[index] as? UIScrollView, let panOffset = panOffsets[index] {
                scroll.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentOffset))
                scroll.contentOffset.y = panOffset
                panOffsets[index] = nil
                scroll.addObserver(self, forKeyPath: #keyPath(UIScrollView.contentOffset), options: .new, context: nil)
            }

            if let scroll = self.panViews[currentIndex] as? UIScrollView, scrollView == scroll {
                if keyPath == #keyPath(UIScrollView.contentSize) {
                    updateOverlayScrollContentSize(with: scroll)
                } else if keyPath == #keyPath(UIScrollView.contentOffset) {
                    freezeBottomContentOffsetWhileNavigating(for: scroll)
                }
            }
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        contentOffsets[currentIndex] = scrollView.contentOffset.y
        let topHeight = bottomView.frame.minY - dataSource.minHeaderHeight()
        if scrollView.contentOffset.y + 0.1 < topHeight { // 0.1 prevents pages from jumping at the boundary
            self.containerScrollView.contentOffset.y = scrollView.contentOffset.y
            self.panViews.forEach({ arg0 in
                let (_, value) = arg0
                (value as? UIScrollView)?.contentOffset.y = 0
            })
            contentOffsets.removeAll()
        } else {
            self.containerScrollView.contentOffset.y = topHeight
            let panOffset = scrollView.contentOffset.y - self.containerScrollView.contentOffset.y
            (self.panViews[currentIndex] as? UIScrollView)?.contentOffset.y = panOffset
        }

        let progress = self.containerScrollView.contentOffset.y / topHeight
        self.delegate?.pinnedHeaderScrollView(self.containerScrollView, didUpdate: progress)
    }
}

// MARK: BottomPageDelegate

extension PinnedHeaderWithPagesViewController: BottomPageDelegate {
    func pinnedHeaderPageViewController(_ currentViewController: UIViewController?, didSelectPageAt index: Int) {
        let prevIndex = currentIndex
        panOffsets[prevIndex] = (panViews[prevIndex] as? UIScrollView)?.contentOffset.y
        currentIndex = index
        if let offset = contentOffsets[index] {
            self.overlayScrollView.contentOffset.y = offset
        } else {
            self.overlayScrollView.contentOffset.y = self.containerScrollView.contentOffset.y
        }

        if let vc = currentViewController, self.panViews[currentIndex] == nil {
            self.panViews[currentIndex] = vc.scrollView()
        }

        if let panView = self.panViews[currentIndex] {
            updateOverlayScrollContentSize(with: panView)
        }

        delegate?.pinnedHeaderDidSelectPage(at: index)
    }
}

extension PinnedHeaderWithPagesViewController {
    static func add(parent: UIViewController, to child: UIViewController, to: UIView? = nil, frame: CGRect? = nil) {
        parent.addChild(child)
        if let frame = frame {
            child.view.frame = frame
        }
        if let toView = to {
            toView.addSubview(child.view)
        } else {
            parent.view.addSubview(child.view)
        }
        child.didMove(toParent: parent)
    }

    public static func configure(viewController: UIViewController, with dataSource: PinnedHeaderDataSource, delegate: PinnedHeaderDelegate? = nil) {
        let vc = PinnedHeaderWithPagesViewController()
        vc.dataSource = dataSource
        vc.delegate = delegate
        add(parent: viewController, to: vc)
        vc.view.pinEdges(to: viewController.view)
    }
}

private extension UIView {
    func constraint(to view: UIView, attribute: NSLayoutConstraint.Attribute, secondAttribute: NSLayoutConstraint.Attribute, inset: CGFloat = 0) {
        self.translatesAutoresizingMaskIntoConstraints = false
        let c = NSLayoutConstraint(item: self,
                                   attribute: attribute,
                                   relatedBy: .equal,
                                   toItem: view,
                                   attribute: secondAttribute,
                                   multiplier: 1,
                                   constant: inset)
        c.isActive = true
    }

    func pinEdges(to view: UIView, insets: UIEdgeInsets = .zero) {
        self.translatesAutoresizingMaskIntoConstraints = false

        let top = NSLayoutConstraint(item: self,
                                     attribute: .top,
                                     relatedBy: .equal,
                                     toItem: view,
                                     attribute: .top,
                                     multiplier: 1,
                                     constant: insets.top)

        let bottom = NSLayoutConstraint(item: self,
                                        attribute: .bottom,
                                        relatedBy: .equal,
                                        toItem: view,
                                        attribute: .bottom,
                                        multiplier: 1,
                                        constant: insets.bottom)

        let leading = NSLayoutConstraint(item: self,
                                         attribute: .leading,
                                         relatedBy: .equal,
                                         toItem: view,
                                         attribute: .leading,
                                         multiplier: 1,
                                         constant: insets.left)

        let trailing = NSLayoutConstraint(item: self,
                                          attribute: .trailing,
                                          relatedBy: .equal,
                                          toItem: view,
                                          attribute: .trailing,
                                          multiplier: 1,
                                          constant: insets.right)
        top.isActive = true
        bottom.isActive = true
        leading.isActive = true
        trailing.isActive = true
    }
}
