import SwiftUI
import StoreKit

/// Presents the thank-you card from the top of the app, so an Ask to Buy approval that
/// lands while someone is in the guide still gets thanked. Its own container keeps this
/// cover apart from RootView's player cover.
struct TipThanksHost<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Bindable private var tipJar = TipJar.shared

    var body: some View {
        ZStack { content() }
            .fullScreenCover(isPresented: $tipJar.showThanks) {
                TipThanksView(line: tipJar.thanksLine) { tipJar.dismissThanks() }
            }
    }
}

/// Full-screen card shown once per tip. One button, focused from the start.
struct TipThanksView: View {
    var line: String = TipJarLogic.thanksLine
    let onDismiss: () -> Void

    @FocusState private var okFocused: Bool

    var body: some View {
        ZStack {
            TipCardBackground()

            VStack(spacing: 28) {
                Text(TipJarLogic.thanksTitle)
                    .font(.custom("DMMono-Medium", size: 64))
                    .foregroundStyle(.white)

                Text(line)
                    .font(.custom("DMMono-Regular", size: 30))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)

                Button(action: onDismiss) {
                    TipCardButtonLabel(title: "OK", isFocused: okFocused, minWidth: 220)
                }
                .buttonStyle(TipCardButtonStyle())
                .focused($okFocused)
                .padding(.top, 24)
                .accessibilityLabel("OK")
            }
            .padding(80)
        }
        .defaultFocus($okFocused, true)
        .onAppear { okFocused = true }
        .onExitCommand(perform: onDismiss)
    }
}

// MARK: - Quantity sheet

/// Picked a tip row: choose how many (1 to 5), see the total, then tip or cancel.
/// The purchase itself starts after this sheet is gone, so the thank-you card never
/// races its dismissal.
struct TipQuantityView: View {
    let product: Product
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    @State private var quantity = 1
    @FocusState private var focus: Field?

    private enum Field: Hashable { case minus, plus, tip, cancel }

    private var title: String {
        TipProduct(rawValue: product.id)?.rowTitle ?? product.displayName.uppercased()
    }

    private var totalText: String {
        TipJarLogic.totalText(price: product.price, quantity: quantity, format: product.priceFormatStyle)
    }

    var body: some View {
        ZStack {
            TipCardBackground()

            VStack(spacing: 36) {
                Text(title)
                    .font(.custom("DMMono-Medium", size: 56))
                    .foregroundStyle(.white)

                HStack(spacing: 56) {
                    stepButton("-", field: .minus, enabled: quantity > TipJarLogic.quantityRange.lowerBound) {
                        quantity = TipJarLogic.clampQuantity(quantity - 1)
                    }
                    .accessibilityLabel("Fewer")
                    .accessibilityIdentifier("tip_quantity_minus")

                    Text("\(quantity)")
                        .font(.custom("DMMono-Medium", size: 120))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(minWidth: 160)
                        .accessibilityIdentifier("tip_quantity_value")

                    stepButton("+", field: .plus, enabled: quantity < TipJarLogic.quantityRange.upperBound) {
                        quantity = TipJarLogic.clampQuantity(quantity + 1)
                    }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("tip_quantity_plus")
                }

                VStack(spacing: 8) {
                    Text("\(product.displayPrice) each")
                        .font(.custom("DMMono-Regular", size: 24))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Paid through your Apple account")
                        .font(.custom("DMMono-Regular", size: 20))
                        .foregroundStyle(.white.opacity(0.5))
                }

                HStack(spacing: 32) {
                    Button { onConfirm(quantity) } label: {
                        TipCardButtonLabel(title: "TIP \(totalText)", isFocused: focus == .tip, minWidth: 300)
                    }
                    .buttonStyle(TipCardButtonStyle())
                    .focused($focus, equals: .tip)
                    .accessibilityIdentifier("tip_confirm")

                    Button(action: onCancel) {
                        TipCardButtonLabel(title: "CANCEL", isFocused: focus == .cancel, minWidth: 220)
                    }
                    .buttonStyle(TipCardButtonStyle())
                    .focused($focus, equals: .cancel)
                    .accessibilityIdentifier("tip_cancel")
                }
                .padding(.top, 12)
            }
            .padding(80)
        }
        .defaultFocus($focus, .tip)
        .onAppear { focus = .tip }
        .onExitCommand(perform: onCancel)
    }

    /// Stays focusable at the ends of the range (dimmed) so focus never jumps away when
    /// the count hits 1 or 5.
    private func stepButton(_ symbol: String, field: Field, enabled: Bool, action: @escaping () -> Void) -> some View {
        let isFocused = focus == field
        return Button(action: action) {
            Text(symbol)
                .font(.custom("DMMono-Medium", size: 56))
                .foregroundStyle(isFocused ? .black : .white.opacity(enabled ? 1 : 0.3))
                .frame(width: 110, height: 110)
                .background(
                    Circle().fill(isFocused ? Color("BrandCyan") : .white.opacity(0.07))
                )
                .overlay(
                    Circle().stroke(Color("BrandCyan").opacity(isFocused ? 0 : (enabled ? 0.5 : 0.2)), lineWidth: 1.5)
                )
                .scaleEffect(isFocused ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(TipCardButtonStyle())
        .focused($focus, equals: field)
    }
}

// MARK: - Shared pieces

private struct TipCardBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.04, blue: 0.10),
                Color(red: 0.05, green: 0.05, blue: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct TipCardButtonLabel: View {
    let title: String
    let isFocused: Bool
    let minWidth: CGFloat

    var body: some View {
        Text(title)
            .font(.custom("DMMono-Medium", size: 26))
            .foregroundStyle(isFocused ? .black : .white)
            .frame(minWidth: minWidth)
            .padding(.vertical, 18)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFocused ? Color("BrandCyan") : .white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color("BrandCyan").opacity(isFocused ? 0 : 0.5), lineWidth: 1.5)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

/// No system focus platter; the label draws its own focused state, like the Settings rows.
private struct TipCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
