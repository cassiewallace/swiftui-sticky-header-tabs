//
//  Protocols.swift
//
//  Created by Ulises Giacoman on 9/9/25.
//

import UIKit

@MainActor
protocol BottomPageDelegate: AnyObject {
    func pinnedHeaderPageViewController(_ currentViewController: UIViewController?, didSelectPageAt index: Int)
}

@MainActor
protocol PagerAwareProtocol: AnyObject {
    var pageDelegate: BottomPageDelegate? { get set }
    var currentViewController: UIViewController? { get }
    var pagerTabHeight: CGFloat? { get }
}

@MainActor
protocol PannableViewsProtocol {
    func scrollView() -> UIView
}

@MainActor
public protocol SwiftUIViewReadinessProtocol: AnyObject {
    func notifySwiftUIViewReady()
}

@MainActor
protocol SwiftUIHostingProtocol: AnyObject {
    func setReadinessDelegate(_ delegate: SwiftUIViewReadinessProtocol?)
}

extension UIViewController: PannableViewsProtocol {
    @objc open func scrollView() -> UIView {
        if let scroll = self.view.subviews.first(where: { $0 is UIScrollView }) {
            return scroll
        } else {
            return self.view
        }
    }
}

@MainActor
protocol PinnedHeaderDataSource: AnyObject {
    func headerViewController() -> UIViewController
    func bottomViewController() -> UIViewController & PagerAwareProtocol
    func minHeaderHeight() -> CGFloat
}

@MainActor
protocol PinnedHeaderDelegate: AnyObject {
    func pinnedHeaderScrollView(_ scrollView: UIScrollView, didUpdate progress: CGFloat)
    func pinnedHeaderScrollViewDidLoad(_ scrollView: UIScrollView)
    func pinnedHeaderDidSelectPage(at index: Int)
}
