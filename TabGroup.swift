//
//  TabGroup.swift
//
//  Created by Cassie Wallace on 5/9/25.
//

import SwiftUI

/// A horizontally scrollable tab group that displays selectable tab items with an animated underline.
/// - Displays up to five tabs with evenly distributed width. If a longer title is passed in, the width increases.
/// - For more than five tabs, uses a fixed minimum width and enables horizontal scrolling.
/// - Syncs the selected tab index with a binding.
public struct TabGroup: View {
    // MARK: - Private Properties

    /// The measured widths of each tab's label for layout calculations.
    @State private var labelWidths: [Int: CGFloat] = [:]

    /// An array of titles for each tab.
    private let titles: [String]

    /// A binding to the currently selected tab index.
    @Binding private var selectedIndex: Int

    let isOffsetControlledByParent: Bool

    /// The fractional scroll offset between tabs, used to interpolate the animated underline position.
    /// Typically provided by an external `PageView` or equivalent component.
    private let tabOffset: CGFloat

    /// The animation duration for the sliding underline.
    private var animationDuration: TimeInterval = 0.3

    /// The horizontal padding of each tab. This is passed into TabItem to ensure calculations are synced.
    private var horizontalPadding: CGFloat = Spacing.m

    private var leadingPadding: CGFloat

    /// The height of the tab group, scalable for accessibility.
    @ScaledMetric private var height: CGFloat = 40

    /// Tap action
    private var onTapped: ((Int) -> Void)?

    // MARK: - Lifecycle

    /// Initializes a `TabGroup`.
    /// - Parameters:
    ///   - titles: An array of tab titles.
    ///   - selectedIndex: A binding to the currently selected tab index.
    ///   - tabOffset: The fractional offset between tabs used to animate the underline.
    public init(titles: [String], selectedIndex: Binding<Int>, tabOffset: CGFloat, isOffsetControlledByParent: Bool = true, leadingPadding: CGFloat = Spacing.none, onTapped: ((Int) -> Void)? = nil) {
        self.titles = titles
        self.isOffsetControlledByParent = isOffsetControlledByParent
        self._selectedIndex = selectedIndex
        self.tabOffset = tabOffset
        self.leadingPadding = leadingPadding
        self.onTapped = onTapped
    }

    // MARK: - Views

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { _ in
                ZStack(alignment: .bottomLeading) {
                    HStack(spacing: Spacing.none) {
                        ForEach(titles.indices, id: \.self) { index in
                            TabItem(
                                titles[index],
                                index: index,
                                horizontalPadding: horizontalPadding,
                                isSelected: selectedIndex == index,
                                minWidth: 0
                            ) {
                                withAnimation(.easeInOut(duration: animationDuration)) {
                                    selectedIndex = index
                                    onTapped?(index)
                                }
                            }
                        }
                    }
                    .padding(.leading, leadingPadding - horizontalPadding)
                    .backgroundPreferenceValue(TabItemPreferenceKey.self) { preferences in
                        GeometryReader { proxy in

                            let frames = titles.indices.compactMap { index in
                                preferences[index].map { proxy[$0] }
                            }

                            if !frames.isEmpty {
                                if !isOffsetControlledByParent {
                                    let maxIndex = CGFloat(frames.count - 1)
                                    let baseOffset = abs(tabOffset - CGFloat(selectedIndex)) > 0.9 ? CGFloat(selectedIndex) : tabOffset
                                    let offset = min(max(baseOffset, 0), maxIndex)

                                    // Determine the two tab indices between which the scrollOffset lies.
                                    let lowerIndex = Int(floor(offset))
                                    let upperIndex = min(lowerIndex + 1, frames.count - 1)

                                    // Calculate the fractional distance between the two tabs.
                                    let percent = offset - CGFloat(lowerIndex)

                                    // Retrieve the frames for the lower and upper tab items.
                                    let lowerFrame = frames[lowerIndex]
                                    let upperFrame = frames[upperIndex]

                                    let interpolatedX = lowerFrame.minX + (upperFrame.minX - lowerFrame.minX) * percent
                                    let interpolatedWidth = lowerFrame.width + (upperFrame.width - lowerFrame.width) * percent

                                    // Draw the animated underline at the interpolated position.
                                    Rectangle()
                                        .fill(Color.primary)
                                        .frame(width: interpolatedWidth, height: 2)
                                        .offset(x: interpolatedX, y: lowerFrame.maxY + Spacing.xs + 1)
                                } else {
                                    // Clamp scrollOffset to ensure it's within valid index bounds.
                                    let maxIndex = CGFloat(frames.count - 1)
                                    let offset = min(max(tabOffset, 0), maxIndex)

                                    // Determine the two tab indices between which the scrollOffset lies.
                                    let lowerIndex = Int(floor(offset))
                                    let upperIndex = min(lowerIndex + 1, frames.count - 1)

                                    // Calculate the fractional distance between the two tabs.
                                    let percent = offset - CGFloat(lowerIndex)

                                    // Retrieve the frames for the lower and upper tab items.
                                    let lowerFrame = frames[lowerIndex]
                                    let upperFrame = frames[upperIndex]

                                    // Interpolate the underline's x-position and width between the two frames.
                                    let interpolatedX = lowerFrame.minX + (upperFrame.minX - lowerFrame.minX) * percent
                                    let interpolatedWidth = lowerFrame.width + (upperFrame.width - lowerFrame.width) * percent

                                    // Draw the animated underline at the interpolated position.
                                    Rectangle()
                                        .fill(Color.primary)
                                        .frame(width: interpolatedWidth, height: 2)
                                        .offset(x: interpolatedX, y: lowerFrame.maxY + Spacing.xs + 1)
                                }
                            }
                        }
                    }
                }
                .onPreferenceChange(TabLabelWidthPreferenceKey.self) { labelWidths = $0 }
                .sensoryFeedback(.selection, trigger: selectedIndex)
            }
        }
        .overlay(
            Divider(),
            alignment: .bottom
        )
        .frame(height: height)
    }
}

/// A single tab item used in `TabGroup`, with visual feedback for selection and layout support for the animated underline.
private struct TabItem: View {
    /// The text label shown for the tab.
    private let label: String

    /// The index of this tab within the group.
    private let index: Int

    /// Horizontal padding applied to the label.
    private let horizontalPadding: CGFloat

    /// Whether the tab is currently selected.
    private let isSelected: Bool

    /// The minimum width the tab should take up.
    private let minWidth: CGFloat

    /// The height of the tab, scalable for accessibility.
    @ScaledMetric private var height: CGFloat = 40

    /// Action to perform when the tab is tapped.
    private let action: () -> Void

    /// Initializes a `TabItem`.
    /// - Parameters:
    ///   - label: The title displayed on the tab.
    ///   - index: The index of this tab.
    ///   - horizontalPadding: The horizontal padding of the tab.
    ///   - isSelected: Whether this tab is currently selected.
    ///   - minWidth: The minimum width of the tab.
    ///   - action: The action to perform when the tab is tapped.
    init(
        _ label: String,
        index: Int,
        horizontalPadding: CGFloat,
        isSelected: Bool,
        minWidth: CGFloat,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.index = index
        self.horizontalPadding = horizontalPadding
        self.isSelected = isSelected
        self.minWidth = minWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(isSelected ? .primary : .secondary)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .anchorPreference(
                                key: TabItemPreferenceKey.self,
                                value: .bounds
                            ) { [index: $0] }
                            .preference(
                                key: TabLabelWidthPreferenceKey.self,
                                value: [index: geometry.size.width]
                            )
                    }
                )
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, Spacing.xs)
        .frame(height: height)
        .frame(minWidth: minWidth)
        .buttonStyle(.plain)
    }
}

/// A preference key used to store anchor bounds for each tab item,
/// enabling layout of the animated underline in the parent `TabGroup`.
private struct TabItemPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// A preference key used to collect the measured label widths of tab items.
/// Enables the parent `TabGroup` to dynamically adjust tab layout.
private struct TabLabelWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

#Preview("Tab Group") {
    @Previewable @State var selectedIndex = 0
    @Previewable @State var tabOffset: CGFloat = 0
    let titles = ["Me", "Insights", "A Really Long Tab Title", "Posts", "About", "You"]
    let shortTitles = titles.filter { $0.count < 10 }

    VStack(spacing: Spacing.m) {
        TabGroup(titles: Array(shortTitles[..<1]), selectedIndex: $selectedIndex, tabOffset: tabOffset)
        TabGroup(titles: Array(shortTitles[..<2]), selectedIndex: $selectedIndex, tabOffset: tabOffset)
        TabGroup(titles: Array(shortTitles[..<3]), selectedIndex: $selectedIndex, tabOffset: tabOffset)
        TabGroup(titles: Array(shortTitles[..<4]), selectedIndex: $selectedIndex, tabOffset: tabOffset)
        TabGroup(titles: Array(shortTitles[..<5]), selectedIndex: $selectedIndex, tabOffset: tabOffset)
        TabGroup(titles: Array(titles[..<3]), selectedIndex: $selectedIndex, tabOffset: tabOffset)
        TabGroup(titles: Array(titles[..<5]), selectedIndex: $selectedIndex, tabOffset: tabOffset)
        TabGroup(titles: Array(titles[..<2]) + Array(titles[..<2] + Array(titles[..<2])), selectedIndex: $selectedIndex, tabOffset: tabOffset)
    }
}

#Preview("Tab Item") {
    VStack(spacing: Spacing.xl) {
        TabItem("Selected", index: 0, horizontalPadding: Spacing.l, isSelected: true, minWidth: 70, action: {})
        TabItem("Unselected", index: 1, horizontalPadding: Spacing.l, isSelected: false, minWidth: 70, action: {})
    }
}
