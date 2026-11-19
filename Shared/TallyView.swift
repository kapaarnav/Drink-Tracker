import SwiftUI

struct TallyView: View {
    let count: Int
    var color: Color = .primary
    var height: CGFloat = 22
    var body: some View {
        GeometryReader { proxy in
            let capacity = max(0, Int(proxy.size.width / 5.6))
            let overflow = count > capacity
            let visible = min(count, max(0, capacity - (overflow ? 3 : 0)))
            HStack(spacing: 0) {
                ForEach(0..<visible, id: \.self) { index in
                    Capsule().fill(color).frame(width: 2, height: height)
                        .padding(.trailing, index % 5 == 4 ? 6 : 3)
                }
                if overflow { Text("…").font(.caption.bold()).foregroundStyle(color) }
                Spacer(minLength: 0)
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: height + 4)
        .accessibilityHidden(true)
    }
}
