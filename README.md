# SwiftUI Sticky Header Tabs

A SwiftUI + UIKit component for building **Twitter/LinkedIn-style profile screens** with a **sticky (pinned) collapsing header**, a smooth **animated tab bar with underline indicator**, and **horizontally-paged, swipeable content**.

---

## What makes this useful

Building a profile-style layout — sticky header that collapses as you scroll, tabs that stay pinned, swipeable pages — involves several tricky problems that this library solves:

- **Smooth underline animation**: the tab bar underline interpolates in real time as you *swipe*, not just on tap
- **Per-page scroll offset memory**: switching tabs doesn't reset the scroll position of previously-visited pages
- **Back-swipe gesture conflict resolution**: left-edge swipe still triggers navigation pop even when a horizontal pager is present
- **SwiftUI / UIKit bridge**: SwiftUI pages work alongside UIKit pages; a `HostingListViewController` helper notifies the pinned-header engine when a SwiftUI scroll view is ready

---

## Components

### `TabGroup` (SwiftUI)

A horizontally scrollable **tab bar with animated underline**. Use it standalone or inside `TabbedPages`.

- Up to 5 tabs are evenly distributed across the full width
- Beyond 5 tabs, a fixed minimum width is used and the bar scrolls horizontally
- The underline position is driven by a `tabOffset: CGFloat` binding, making it trivially connectable to a `UIScrollViewDelegate` for real-time interpolation
- `@ScaledMetric` height supports Dynamic Type

```swift
TabGroup(
    titles: ["Posts", "About", "Connections"],
    selectedIndex: $selectedIndex,
    tabOffset: scrollOffset         // fractional index from your scroll view
)
```

### `TabbedPages` (UIViewControllerRepresentable)

Combines a **sticky/pinned header view controller** with a **paged scroll view** and a `TabGroup` tab bar. Drop it directly into a SwiftUI view.

```swift
TabbedPages(
    header: MyHeaderViewController(),
    pages: [PostsViewController(), AboutViewController()],
    titles: ["Posts", "About"],
    selectedTabIndex: $selectedIndex,
    isHeaderPinned: { isPinned in
        // Called when the header fully collapses / expands
        showCompactNavBar = isPinned
    },
    onPageSwitch: { index in
        print("Switched to page \(index)")
    }
)
```

Without a header, `TabbedPages` renders just the tab bar + paged scroll view:

```swift
TabbedPages(
    pages: [PostsViewController(), AboutViewController()],
    titles: ["Posts", "About"]
)
```

### `PinnedHeaderWithPagesViewController` (UIKit)

The UIKit engine behind `TabbedPages`. You can use it directly for pure UIKit layouts.

Configure it using the static factory method:

```swift
PinnedHeaderWithPagesViewController.configure(
    viewController: self,   // your UIViewController
    with: self,             // PinnedHeaderDataSource
    delegate: self          // PinnedHeaderDelegate (optional)
)
```

Implement `PinnedHeaderDataSource`:

```swift
func headerViewController() -> UIViewController { myHeaderVC }
func bottomViewController() -> UIViewController & PagerAwareProtocol { myPagerVC }
func minHeaderHeight() -> CGFloat { view.safeAreaInsets.top }
```

### `HostingListViewController<Content>` (UIKit)

A `UIHostingController` subclass that implements `SwiftUIHostingProtocol`. Use it to wrap SwiftUI pages that contain a `List` or `ScrollView` so the pinned-header engine can find their scroll view after it's been laid out by SwiftUI.

```swift
let postsVC = HostingListViewController(rootView: PostsView())
```

---

## Requirements

- iOS 17+
- Swift 5.9+
- No external dependencies

---

## Installation

Copy the source files into your project. There is no Swift Package yet — the files have no dependencies beyond SwiftUI, UIKit, and Combine.

Files to include:
```
Spacing.swift
TabGroup.swift
TabbedPages.swift
PinnedHeaderWithPages/
  Protocols.swift
  PinnedHeaderWithPagesViewController.swift
```

---

## How it works

`PinnedHeaderWithPagesViewController` uses a **container/overlay dual-scroll-view pattern**:

- A `containerScrollView` holds the header and the pager stacked vertically
- A transparent `overlayScrollView` sits on top and captures all pan gestures
- As the overlay scrolls, it moves the container until the header is pinned, then hands scroll events to the active page's inner scroll view
- Each page's scroll offset is cached when you switch tabs, so returning to a tab restores its position

Each page's scroll offset is cached when you switch tabs, so returning to a tab restores its position.

---

