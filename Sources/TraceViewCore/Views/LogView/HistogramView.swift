import AppKit
import SwiftUI

// Event-density histogram strip. Buckets are computed on the document
// (see `recomputeHistogram`) so this view just reads the cached result —
// no O(N) pass on every SwiftUI body evaluation, and no duplicate work
// when the same doc is shown in both split panes. Hidden when fewer than
// 10% of entries have parsed timestamps.
struct HistogramView: View {
    @ObservedObject var document: LogDocument
    @EnvironmentObject var themeManager: ThemeManager

    /// Fired when the user clicks a bucket. Caller resolves the bucket's
    /// time range to a concrete entry and navigates. Disabled state is
    /// naturally handled by the histogram being hidden.
    var onBucketClick: (Int) -> Void = { _ in }
    var barHeight: CGFloat = CGFloat(SettingsManager.defaultHistogramHeight)
    var zoomDepth: Int = 0
    var onZoom: (DateInterval) -> Void = { _ in }
    var onZoomOut: () -> Void = {}
    var onZoomAll: () -> Void = {}

    @State private var hoveredBucket: Int?
    @State private var selectionStartX: CGFloat?
    @State private var selectionEndX: CGFloat?
    @State private var selectionChartWidth: CGFloat = 1
    @State private var scrollMonitor = HistogramScrollWheelMonitor()
    @State private var tooltipVisible = false
    @State private var tooltipTask: Task<Void, Never>?
    @State private var tooltipSize: CGSize = .zero

    var body: some View {
        let theme = themeManager.current

        if let bins = document.histogram {
            VStack(spacing: 2) {
                barStrip(bins: bins, theme: theme)
                rangeLabels(bins: bins, theme: theme)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(theme.filterBarBackground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.borderSubtle).frame(height: 1)
            }
            .overlay { bucketTooltip(bins: bins) }
            .onChange(of: hoveredBucket) { _, bucket in
                updateTooltipVisibility(for: bucket)
            }
        }
    }

    @ViewBuilder
    private func barStrip(bins: LogHistogram, theme: any AppTheme) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(bins.bars.indices, id: \.self) { i in
                        interactiveBar(index: i, bins: bins, theme: theme)
                    }
                }

                if let selectionStartX, let selectionEndX {
                    Rectangle()
                        .fill(theme.accentColor.opacity(0.22))
                        .overlay {
                            Rectangle().stroke(theme.accentColor, lineWidth: 1)
                        }
                        .frame(width: abs(selectionEndX - selectionStartX))
                        .offset(x: min(selectionStartX, selectionEndX))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard geometry.size.width > 0, !bins.bars.isEmpty else { return }
                    let fraction = min(max(location.x / geometry.size.width, 0), 1)
                    hoveredBucket = min(
                        bins.bars.count - 1,
                        Int(fraction * CGFloat(bins.bars.count))
                    )
                    scrollMonitor.start { zoomIn in
                        handleScrollZoom(zoomIn: zoomIn, anchorFraction: Double(fraction))
                    }
                case .ended:
                    hoveredBucket = nil
                    scrollMonitor.stop()
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        selectionChartWidth = geometry.size.width
                        if selectionStartX == nil {
                            selectionStartX = boundedX(value.startLocation.x, width: geometry.size.width)
                        }
                        selectionEndX = boundedX(value.location.x, width: geometry.size.width)
                    }
                    .onEnded { value in
                        let width = geometry.size.width
                        let startX = selectionStartX ?? boundedX(value.startLocation.x, width: width)
                        let endX = boundedX(value.location.x, width: width)
                        selectionStartX = nil
                        selectionEndX = nil
                        selectionChartWidth = 1

                        if abs(endX - startX) < 8 {
                            let fraction = width > 0 ? endX / width : 0
                            let index = min(
                                bins.bars.count - 1,
                                max(0, Int(fraction * CGFloat(bins.bars.count)))
                            )
                            onBucketClick(index)
                        } else if width > 0 {
                            let duration = bins.bucketSize * Double(bins.bars.count)
                            let startFraction = Double(min(startX, endX) / width)
                            let endFraction = Double(max(startX, endX) / width)
                            let rangeStart = bins.startTime.addingTimeInterval(duration * startFraction)
                            let rangeEnd = bins.startTime.addingTimeInterval(duration * endFraction)
                            if rangeStart < rangeEnd {
                                onZoom(DateInterval(start: rangeStart, end: rangeEnd))
                            }
                        }
                    }
            )
        }
        .onDisappear { scrollMonitor.stop() }
        .frame(height: barHeight)
        .background(theme.borderSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(alignment: .trailing) {
            // "Now" marker at the trailing edge
            Rectangle()
                .fill(theme.accentColor)
                .frame(width: 1.5)
        }
    }

    /// Zooms in by halving the visible span around the cursor, or steps
    /// back one zoom level. Reads the live histogram so repeated scrolls
    /// without moving the mouse keep zooming from the current view.
    private func handleScrollZoom(zoomIn: Bool, anchorFraction: Double) {
        guard zoomIn else {
            onZoomOut()
            return
        }
        guard let bins = document.histogram, !bins.bars.isEmpty else { return }
        let duration = bins.bucketSize * Double(bins.bars.count)
        let newDuration = duration / 2
        let anchor = bins.startTime.addingTimeInterval(duration * anchorFraction)
        let start = anchor.addingTimeInterval(-newDuration * anchorFraction)
        onZoom(DateInterval(start: start, duration: newDuration))
    }

    @ViewBuilder
    private func interactiveBar(index i: Int, bins: LogHistogram, theme: any AppTheme) -> some View {
        ZStack(alignment: .bottom) {
            shadowOverlay(forBucket: i, bins: bins, theme: theme)
            barColumn(
                bar: bins.bars[i],
                maxTotal: bins.maxTotal,
                theme: theme,
                isHovered: hoveredBucket == i
            )
        }
        .contentShape(Rectangle())
        .onTapGesture { onBucketClick(i) }
        .onHover { hovering in
            if hovering {
                hoveredBucket = i
            } else if hoveredBucket == i {
                hoveredBucket = nil
            }
        }
    }

    /// Single tooltip for the hovered bucket, drawn below the histogram
    /// (not above — the strip sits near the top of the window, so an
    /// upward tooltip gets clipped) and clamped horizontally inside the pane.
    @ViewBuilder
    private func bucketTooltip(bins: LogHistogram) -> some View {
        GeometryReader { geometry in
            if tooltipVisible, selectionStartX == nil,
               let i = hoveredBucket, bins.bars.indices.contains(i) {
                let chartWidth = max(geometry.size.width - 28, 1)
                let barCenterX = 14 + (CGFloat(i) + 0.5) * chartWidth / CGFloat(bins.bars.count)
                let halfWidth = tooltipSize.width / 2
                let x = max(halfWidth + 4, min(barCenterX, geometry.size.width - halfWidth - 4))

                Text(tooltipText(for: i, histogram: bins))
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    }
                    .fixedSize()
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: HistogramTooltipSizeKey.self, value: proxy.size)
                        }
                    }
                    .position(x: x, y: geometry.size.height + 4 + tooltipSize.height / 2)
            }
        }
        .allowsHitTesting(false)
        .onPreferenceChange(HistogramTooltipSizeKey.self) { tooltipSize = $0 }
    }

    private func updateTooltipVisibility(for bucket: Int?) {
        tooltipTask?.cancel()
        guard bucket != nil else {
            tooltipVisible = false
            return
        }
        // Once shown, the tooltip follows the pointer bar-to-bar immediately.
        guard !tooltipVisible else { return }
        tooltipTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            tooltipVisible = true
        }
    }

    @ViewBuilder
    private func rangeLabels(bins: LogHistogram, theme: any AppTheme) -> some View {
        HStack(spacing: 10) {
            Text(bins.startLabel)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.tertiaryText)

            Spacer(minLength: 4)

            Text(
                selectedRangeLabel(bins: bins)
                    ?? hoveredSlotLabel(bins: bins)
                    ?? (zoomDepth > 0 ? "Zoomed range" : "Drag to zoom")
            )
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(1)
                .fixedSize()

            Spacer(minLength: 4)

            Button(action: onZoomOut) {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(zoomDepth == 0)
            .opacity(zoomDepth == 0 ? 0.45 : 1)
            .hoverTooltip("Zoom out one level", edge: .top, delay: .milliseconds(150))

            Button(action: onZoomAll) {
                Label("Zoom All", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(zoomDepth == 0)
            .opacity(zoomDepth == 0 ? 0.45 : 1)
            .hoverTooltip("Reset histogram to show all time", edge: .top, delay: .milliseconds(150))

            Spacer(minLength: 4)

            Text(bins.endLabel)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.tertiaryText)
        }
    }

    /// Faint "all-time peak" ghost rendered behind the solid bar. Returns
    /// EmptyView when the bucket has no shadow recorded — most buckets
    /// most of the time. Color is theme.errorText at 0.25 alpha (single
    /// uniform color; the ghost simplifies away the err/warn/info
    /// breakdown, just signaling "there was a spike here at some point").
    @ViewBuilder
    private func shadowOverlay(forBucket index: Int, bins: LogHistogram, theme: any AppTheme) -> some View {
        if let shadow = bins.shadows.first(where: { $0.bucketIndex == index }) {
            GeometryReader { geo in
                let height = geo.size.height * CGFloat(shadow.peakCount) / CGFloat(max(bins.maxTotal, 1))
                Rectangle()
                    .fill(theme.errorText.opacity(0.25))
                    .frame(height: height)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    @ViewBuilder
    private func barColumn(bar: LogHistogram.Bar, maxTotal: Int, theme: any AppTheme, isHovered: Bool) -> some View {
        let heightFactor = maxTotal == 0 ? 0.0 : Double(bar.total) / Double(maxTotal)
        GeometryReader { geo in
            let fullH = geo.size.height
            let barH = fullH * heightFactor
            let total = CGFloat(max(bar.total, 1))
            let errorHeight = barH * CGFloat(bar.err) / total
            let warningHeight = barH * CGFloat(bar.warn) / total
            let infoHeight = barH * CGFloat(bar.info) / total
            ZStack {
                // Hover column highlight — covers the full bucket cell,
                // not just the bar height, so tiny buckets are still an
                // obvious click target.
                if isHovered {
                    Rectangle()
                        .fill(theme.accentColor.opacity(0.18))
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(theme.badgeText(for: .error))
                            .frame(height: errorHeight)
                        Rectangle()
                            .fill(theme.badgeText(for: .warning))
                            .frame(height: warningHeight)
                        Rectangle()
                            .fill(theme.badgeText(for: .info))
                            .frame(height: infoHeight)
                    }
                    .frame(height: barH, alignment: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tooltipText(for bucketIndex: Int, histogram: LogHistogram) -> String {
        let range = histogram.timeRange(forBucket: bucketIndex)
        let startLabel = Self.tooltipTimeFormatter.string(from: range.start)
        let endLabel = Self.tooltipTimeFormatter.string(from: range.end)
        let count = histogram.bars[bucketIndex].total
        let countLabel = count == 1 ? "1 event" : "\(count) events"
        return "\(startLabel) – \(endLabel)\n\(countLabel)"
    }

    private func hoveredSlotLabel(bins: LogHistogram) -> String? {
        guard let hoveredBucket, bins.bars.indices.contains(hoveredBucket) else { return nil }
        let range = bins.timeRange(forBucket: hoveredBucket)
        let start = Self.slotTimeFormatter.string(from: range.start)
        let end = Self.slotTimeFormatter.string(from: range.end)
        return "\(start) – \(end)"
    }

    private func selectedRangeLabel(bins: LogHistogram) -> String? {
        guard let selectionStartX, let selectionEndX,
              abs(selectionEndX - selectionStartX) >= 8 else { return nil }
        let duration = bins.bucketSize * Double(bins.bars.count)
        let startFraction = Double(min(selectionStartX, selectionEndX) / selectionChartWidth)
        let endFraction = Double(max(selectionStartX, selectionEndX) / selectionChartWidth)
        let start = bins.startTime.addingTimeInterval(duration * startFraction)
        let end = bins.startTime.addingTimeInterval(duration * endFraction)
        return "\(Self.slotTimeFormatter.string(from: start)) – \(Self.slotTimeFormatter.string(from: end))"
    }

    private func boundedX(_ value: CGFloat, width: CGFloat) -> CGFloat {
        min(max(value, 0), width)
    }

    private static let tooltipTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy HH:mm:ss"
        return f
    }()

    private static let slotTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

/// Captures scroll-wheel events while the pointer is over the histogram.
/// SwiftUI has no scroll-wheel modifier on macOS, so this installs an
/// NSEvent local monitor only for the duration of the hover.
final class HistogramScrollWheelMonitor {
    private var monitor: Any?
    private var handler: ((Bool) -> Void)?
    private var accumulatedDelta: CGFloat = 0
    private var lastZoom = Date.distantPast

    func start(handler: @escaping (Bool) -> Void) {
        self.handler = handler
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            self.handle(event)
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        handler = nil
        accumulatedDelta = 0
    }

    private func handle(_ event: NSEvent) {
        // Trackpad momentum would otherwise zoom through every level.
        guard event.momentumPhase.isEmpty else { return }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }

        if (delta > 0) != (accumulatedDelta > 0) {
            accumulatedDelta = 0
        }
        accumulatedDelta += delta

        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 24 : 1
        guard abs(accumulatedDelta) >= threshold,
              Date().timeIntervalSince(lastZoom) > 0.15 else { return }

        let zoomIn = accumulatedDelta > 0
        accumulatedDelta = 0
        lastZoom = Date()
        handler?(zoomIn)
    }

    deinit { stop() }
}

private struct HistogramTooltipSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
