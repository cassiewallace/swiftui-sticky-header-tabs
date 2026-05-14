//
//  TabbedPages.swift
//
//  Created by Ulises Giacoman on 9/15/25.
//

import Combine
import SwiftUI
import UIKit

private protocol TabSelectable {
    func setSelectedTabIndex(_ index: Int)
    var pagerVC: PagerViewController { get }
}

extension TabSelectable {
    func setSelectedTabIndex(_ index: Int) {
        Task { @MainActor in
            pagerVC.selectPage(at: index)
        }
    }
}

public struct TabbedPages: UIViewControllerRepresentable {
    private let header: UIViewController?
    private let pages: [UIViewController]
    private let titles: [String]?
    private let selectedTabIndex: Binding<Int>?
    private let isHeaderPinned: ((Bool) -> Void)?
    private let onPageSwitch: (Int) -> Void

    public init(header: UIViewController? = nil,
                pages: [UIViewController],
                titles: [String]? = nil,
                selectedTabIndex: Binding<Int>? = nil,
                isHeaderPinned: ((Bool) -> Void)? = nil,
                onPageSwitch: @escaping (Int) -> Void = { _ in })
    {
        self.header = header
        self.pages = pages
        self.titles = titles
        self.selectedTabIndex = selectedTabIndex
        self.isHeaderPinned = isHeaderPinned
        self.onPageSwitch = onPageSwitch
    }

    public func makeUIViewController(context _: Context) -> UIViewController {
        if let header = header {
            return TabbedPagesViewController(
                headerVC: header,
                pages: pages,
                initialSelectedIndex: selectedTabIndex?.wrappedValue ?? 0,
                isHeaderPinned: isHeaderPinned,
                onPageSwitch: onPageSwitch,
                selectedTabBinding: selectedTabIndex
            )
        } else {
            return TabbedPagesWithoutHeaderViewController(
                pages: pages,
                initialSelectedIndex: selectedTabIndex?.wrappedValue ?? 0,
                onPageSwitch: onPageSwitch,
                selectedTabBinding: selectedTabIndex
            )
        }
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context _: Context) {
        if let selectedTabIndex, let controller = uiViewController as? TabSelectable {
            controller.setSelectedTabIndex(selectedTabIndex.wrappedValue)
        }

        let currentTitles = titles ?? pages.map { $0.title ?? "" }
        if let tabbedPagesVC = uiViewController as? TabbedPagesViewController {
            tabbedPagesVC.pagerVC.updateTabTitles(currentTitles)
        } else if let tabbedPagesWithoutHeaderVC = uiViewController as? TabbedPagesWithoutHeaderViewController {
            tabbedPagesWithoutHeaderVC.pagerVC.updateTabTitles(currentTitles)
        }
    }
}

final class TabbedPagesViewController: UIViewController, PinnedHeaderDataSource, PinnedHeaderDelegate, TabSelectable {
    private let headerVC: UIViewController
    let pagerVC: PagerViewController

    private var isHeaderPinned: Bool = false
    private var isHeaderPinnedCallBack: ((Bool) -> Void)?
    private var onPageSwitchCallback: (Int) -> Void
    private var selectedTabBinding: Binding<Int>?

    init(headerVC: UIViewController,
         pages: [UIViewController],
         initialSelectedIndex: Int,
         isHeaderPinned: ((Bool) -> Void)?,
         onPageSwitch: @escaping (Int) -> Void,
         selectedTabBinding: Binding<Int>?)
    {
        self.headerVC = headerVC
        let safeInitialIndex = pages.isEmpty ? 0 : max(0, min(initialSelectedIndex, pages.count - 1))
        self.pagerVC = PagerViewController(pages: pages, initialIndex: safeInitialIndex)
        self.isHeaderPinnedCallBack = isHeaderPinned
        self.onPageSwitchCallback = onPageSwitch
        self.selectedTabBinding = selectedTabBinding
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        PinnedHeaderWithPagesViewController.configure(viewController: self, with: self, delegate: self)
    }

    func headerViewController() -> UIViewController { headerVC }
    func bottomViewController() -> UIViewController & PagerAwareProtocol { pagerVC }
    func minHeaderHeight() -> CGFloat { view.safeAreaInsets.top }

    func pinnedHeaderScrollView(_: UIScrollView, didUpdate progress: CGFloat) {
        // Due to a magic number, we check 98% rather than 100%
        // We also don't want to spam the closure
        let newValue = progress > 0.98
        if newValue != isHeaderPinned {
            isHeaderPinnedCallBack?(newValue)
            isHeaderPinned = newValue
        }
    }

    func pinnedHeaderScrollViewDidLoad(_: UIScrollView) {
        // Called when the container finishes wiring scroll views
    }

    func pinnedHeaderDidSelectPage(at index: Int) {
        onPageSwitchCallback(index)
        selectedTabBinding?.wrappedValue = index
    }
}

final class TabbedPagesWithoutHeaderViewController: UIViewController, TabSelectable {
    let pagerVC: PagerViewController
    private var onPageSwitchCallback: (Int) -> Void
    private var selectedTabBinding: Binding<Int>?

    init(pages: [UIViewController],
         initialSelectedIndex: Int,
         onPageSwitch: @escaping (Int) -> Void,
         selectedTabBinding: Binding<Int>?)
    {
        let safeInitialIndex = pages.isEmpty ? 0 : max(0, min(initialSelectedIndex, pages.count - 1))
        self.pagerVC = PagerViewController(pages: pages, initialIndex: safeInitialIndex)
        self.onPageSwitchCallback = onPageSwitch
        self.selectedTabBinding = selectedTabBinding
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        addChild(pagerVC)
        let pagerView = pagerVC.view!
        pagerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pagerView)
        pagerVC.didMove(toParent: self)
        pagerVC.pageDelegate = self

        NSLayoutConstraint.activate([
            pagerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pagerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

extension TabbedPagesWithoutHeaderViewController: BottomPageDelegate {
    func pinnedHeaderPageViewController(_: UIViewController?, didSelectPageAt index: Int) {
        onPageSwitchCallback(index)
        selectedTabBinding?.wrappedValue = index
    }
}

final class PagerViewController: UIViewController, PagerAwareProtocol, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    weak var pageDelegate: BottomPageDelegate?
    var currentViewController: UIViewController? {
        guard currentIndex >= 0, currentIndex < pages.count else { return nil }
        return pages[currentIndex]
    }

    var pagerTabHeight: CGFloat? { 40 }

    private var pages: [UIViewController]
    private var tabs: [String] {
        pages.map { $0.title ?? "" }
    }

    private let adapter = TabBarAdapter()
    private var tabHostController: UIHostingController<TabBarView>?
    private let scrollView = UIScrollView()
    private var currentIndex: Int = 0
    private var selectionCancellable: AnyCancellable?
    private var customPanGesture: UIPanGestureRecognizer?
    private var isAnimatingTabOffset: Bool = false

    init(pages: [UIViewController], initialIndex: Int) {
        self.pages = pages
        super.init(nibName: nil, bundle: nil)

        if pages.isEmpty {
            currentIndex = 0
            adapter.selectedIndex = 0
            adapter.tabOffset = 0
        } else {
            let safeIndex = max(0, min(initialIndex, pages.count - 1))
            currentIndex = safeIndex
            adapter.selectedIndex = safeIndex
            adapter.tabOffset = CGFloat(safeIndex)
            adapter.titles = tabs
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // SwiftUI TabGroup (tab bar)
        let host = UIHostingController(rootView: TabBarView(adapter: adapter))
        tabHostController = host
        addChild(host)
        let hostView = host.view!
        hostView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostView)
        host.didMove(toParent: self)

        // Custom scroll view for pages
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        view.addSubview(scrollView)

        guard !pages.isEmpty else { return }

        for (_, pageVC) in pages.enumerated() {
            addChild(pageVC)
            let pageView = pageVC.view!
            pageView.translatesAutoresizingMaskIntoConstraints = true // Use frame-based layout
            scrollView.addSubview(pageView)
            pageVC.didMove(toParent: self)
        }

        NSLayoutConstraint.activate([
            hostView.topAnchor.constraint(equalTo: view.topAnchor),
            hostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostView.heightAnchor.constraint(equalToConstant: 44),

            scrollView.topAnchor.constraint(equalTo: hostView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Add a custom pan gesture to handle conflicts with interactivePopGestureRecognizer
        setupGestureConflictResolution(for: scrollView)

        selectionCancellable = adapter.$selectedIndex
            .removeDuplicates()
            .sink { [weak self] newIndex in
                self?.selectPage(at: newIndex)
            }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard !pages.isEmpty else { return }

        let width = scrollView.bounds.width
        let height = scrollView.bounds.height

        guard width > 0, height > 0 else { return }

        for (index, pageVC) in pages.enumerated() {
            let pageView = pageVC.view!
            pageView.frame = CGRect(
                x: CGFloat(index) * width,
                y: 0,
                width: width,
                height: height
            )
        }

        scrollView.contentSize = CGSize(width: CGFloat(pages.count) * width, height: height)

        let expectedOffset = CGFloat(currentIndex) * width
        if abs(scrollView.contentOffset.x - expectedOffset) > 1.0 {
            scrollView.contentOffset = CGPoint(x: expectedOffset, y: 0)
        }
    }

    func selectPage(at newIndex: Int) {
        guard !pages.isEmpty, newIndex != currentIndex, newIndex >= 0, newIndex < pages.count else { return }

        // Prevent scroll delegate interference during animation
        isAnimatingTabOffset = true

        // Animate the tab offset
        withAnimation(.easeInOut(duration: 0.3), completionCriteria: .logicallyComplete) {
            adapter.tabOffset = CGFloat(newIndex)
        } completion: { [weak self] in
            self?.isAnimatingTabOffset = false
        }

        // Scroll to the new page
        let width = scrollView.bounds.width
        let targetOffset = CGPoint(x: CGFloat(newIndex) * width, y: 0)
        scrollView.setContentOffset(targetOffset, animated: true)

        // Update state immediately
        currentIndex = newIndex
        adapter.selectedIndex = newIndex
        pageDelegate?.pinnedHeaderPageViewController(currentViewController, didSelectPageAt: newIndex)
    }

    private func setupGestureConflictResolution(for scrollView: UIScrollView) {
        let panGesture = UIPanGestureRecognizer()
        panGesture.delegate = self
        customPanGesture = panGesture
        view.addGestureRecognizer(panGesture)

        // Make the scroll view's pan gesture work simultaneously with our custom one
        scrollView.panGestureRecognizer.require(toFail: panGesture)
    }

    // MARK: UIScrollViewDelegate (horizontal progress for TabGroup underline)

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        guard !isAnimatingTabOffset else { return }

        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let offset = scrollView.contentOffset.x

        let progress = offset / width
        let clamped = max(0, min(CGFloat(pages.count - 1), progress))
        adapter.tabOffset = clamped
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }

        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let offset = scrollView.contentOffset.x

        let newIndex = Int(round(offset / width))
        let clampedIndex = max(0, min(newIndex, pages.count - 1))

        if clampedIndex != currentIndex {
            currentIndex = clampedIndex
            adapter.selectedIndex = clampedIndex
            adapter.tabOffset = CGFloat(clampedIndex)
            pageDelegate?.pinnedHeaderPageViewController(currentViewController, didSelectPageAt: clampedIndex)
        }
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == customPanGesture else { return true }

        if isAnimatingTabOffset {
            return true
        }

        guard let navigationController,
              navigationController.viewControllers.count > 1
        else {
            return false
        }

        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let location = panGesture.location(in: view)
        let velocity = panGesture.velocity(in: view)

        // Only begin our custom gesture if we're near the left edge with rightward horizontal movement.
        // This blocks the pager's pan gesture and allows the navigation's interactive pop gesture.
        let leftEdgeThreshold: CGFloat = 20
        let isNearLeftEdge = location.x < leftEdgeThreshold
        let isHorizontalGesture = abs(velocity.x) > abs(velocity.y)
        let isRightwardGesture = velocity.x > 0

        return isNearLeftEdge && isHorizontalGesture && isRightwardGesture
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == customPanGesture,
           otherGestureRecognizer == navigationController?.interactivePopGestureRecognizer
        {
            return true
        }
        return false
    }

    func updateTabTitles(_ newTitles: [String]) {
        guard adapter.titles != newTitles else { return }
        adapter.titles = newTitles
    }
}

public final class HostingListViewController<Content: View>: UIHostingController<Content>, SwiftUIHostingProtocol {
    private weak var readinessDelegate: SwiftUIViewReadinessProtocol?
    private var hasNotifiedReadiness = false

    override public func scrollView() -> UIView {
        if let scroll = findScrollView(in: view) {
            return scroll
        }
        return super.scrollView()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if !hasNotifiedReadiness, findScrollView(in: view) != nil {
            hasNotifiedReadiness = true
            readinessDelegate?.notifySwiftUIViewReady()
        }
    }

    public func setReadinessDelegate(_ delegate: SwiftUIViewReadinessProtocol?) {
        self.readinessDelegate = delegate

        if !hasNotifiedReadiness, findScrollView(in: view) != nil {
            hasNotifiedReadiness = true
            delegate?.notifySwiftUIViewReady()
        }
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let s = view as? UIScrollView {
            return s
        }
        for sub in view.subviews {
            if let found = findScrollView(in: sub) {
                return found
            }
        }
        return nil
    }
}

private final class TabBarAdapter: ObservableObject {
    @Published var selectedIndex: Int = 0
    @Published var tabOffset: CGFloat = 0
    @Published var titles: [String] = []
}

private struct TabBarView: View {
    @ObservedObject var adapter: TabBarAdapter

    var body: some View {
        TabGroup(
            titles: adapter.titles,
            selectedIndex: Binding(
                get: { adapter.selectedIndex },
                set: { adapter.selectedIndex = $0 }
            ),
            tabOffset: adapter.tabOffset
        )
        .padding(.horizontal, Spacing.m)
    }
}
