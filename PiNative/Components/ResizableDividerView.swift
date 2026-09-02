import SwiftUI
import AppKit

/// A thin, draggable vertical divider used for the left/right pane
/// boundaries. See implementation plan §F for the exact behavior spec this
/// implements.
struct ResizableDividerView: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    /// `.leading`: the pane being resized sits to the *left* of this divider
    /// (dragging right grows it). `.trailing`: the pane sits to the *right*
    /// of this divider (dragging right shrinks it).
    var edge: Edge
    var onDoubleClick: () -> Void

    @State private var isHovering = false
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(isHovering ? ShellPalette.activeSeparator : ShellPalette.separator)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
            }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            // `NSCursor.push()`/`.pop()` is a stack: if this view disappears
            // (e.g. the pane it borders collapses/closes) while still
            // hovered, `.onHover(false)` may never fire and a pushed resize
            // cursor would be stuck showing forever. Found by adversarial
            // review.
            if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
        // Double-click must win over the zero-distance drag gesture, so it
        // is composed as a high-priority gesture ahead of the base drag.
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                onDoubleClick()
            }
        )
        .gesture(
            // No animation on this path — live drag must track the cursor
            // exactly. Only collapse/expand toggles animate.
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let base = dragStartWidth ?? width
                    if dragStartWidth == nil { dragStartWidth = width }
                    let delta = edge == .leading ? value.translation.width : -value.translation.width
                    width = min(max(base + delta, minWidth), maxWidth)
                }
                .onEnded { _ in
                    dragStartWidth = nil
                }
        )
    }
}

#Preview("Drag + double-click harness") {
    struct Harness: View {
        @State private var leftWidth: CGFloat = 260
        @State private var isLeftVisible = true

        var body: some View {
            HStack(spacing: 0) {
                if isLeftVisible {
                    Color.blue.opacity(0.15)
                        .frame(width: leftWidth)
                        .overlay(Text("\(Int(leftWidth))pt").font(.caption))
                }

                ResizableDividerView(
                    width: $leftWidth,
                    minWidth: 180,
                    maxWidth: 400,
                    edge: .leading,
                    onDoubleClick: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isLeftVisible.toggle()
                        }
                    }
                )

                Color.gray.opacity(0.08)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(Text("Center content"))
            }
            .frame(width: 700, height: 400)
        }
    }

    return Harness()
}
