import SwiftUI
import StoreKit

/// Three plans, one clear list of what changes. Prices come from StoreKit, never hard-coded.
struct PaywallView: View {
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss
    var reason: String
    @State private var selected: String = ProductID.yearly
    @State private var purchasing = false

    private let benefits: [(String, String)] = [
        ("waveform", "Unlimited saved recordings with pitch trails"),
        ("flame", "Full and Bridge-focus daily routines"),
        ("list.bullet", "Every warm-up drill, up to 12 semitones"),
        ("target", "Long Pitch Quests (12 and 16 targets)"),
        ("lock.open", "Everything future updates add"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.badge.plus").font(.system(size: 48)).foregroundStyle(Color.voice)
                        Text("Singwell Pro").font(.largeTitle.weight(.bold))
                        Text(reason).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(benefits, id: \.1) { b in
                            HStack(spacing: 12) {
                                Image(systemName: b.0).foregroundStyle(Color.voice).frame(width: 24)
                                Text(b.1).font(.subheadline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    if store.products.isEmpty {
                        if store.loading { ProgressView().padding() }
                        else if let e = store.lastError { ErrorBanner(message: e) { store.lastError = nil } }
                        else { Text("Plans are loading…").font(.footnote).foregroundStyle(.secondary) }
                    } else {
                        VStack(spacing: 10) {
                            ForEach(store.products, id: \.id) { p in planRow(p) }
                        }
                    }

                    Button {
                        guard let p = store.product(selected) else { return }
                        purchasing = true
                        Task {
                            let ok = await store.purchase(p)
                            purchasing = false
                            if ok { dismiss() }
                        }
                    } label: {
                        HStack {
                            if purchasing { ProgressView().tint(.white) }
                            Text(ctaLabel).bold()
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.voice).controlSize(.large)
                    .disabled(purchasing || store.product(selected) == nil)

                    Button("Restore purchases") { Task { await store.restore(); if store.isPro { dismiss() } } }.font(.footnote)

                    Text("Subscriptions renew automatically until cancelled in Settings › Apple ID › Subscriptions. The free week applies to your first subscription only. Lifetime is a one-time purchase.")
                        .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    HStack(spacing: 16) {
                        Link("Privacy", destination: Legal.privacy)
                        Link("Terms", destination: Legal.terms)
                    }.font(.caption)
                }
                .padding(20)
            }
            .background(Color.pageBackground)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
            .task { if store.products.isEmpty { await store.load() } }
        }
    }

    private var ctaLabel: String {
        guard let p = store.product(selected) else { return "Continue" }
        if let trial = store.trialLabel(for: p) { return "Start \(trial), then \(p.displayPrice)\(periodSuffix(p))" }
        return "Continue · \(p.displayPrice)\(periodSuffix(p))"
    }

    private func periodSuffix(_ p: Product) -> String {
        switch p.id {
        case ProductID.monthly: return "/month"
        case ProductID.yearly: return "/year"
        default: return " once"
        }
    }

    private func planRow(_ p: Product) -> some View {
        let isSelected = selected == p.id
        return Button { selected = p.id } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(planTitle(p)).font(.headline)
                        if p.id == ProductID.yearly { Text("Best value").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Color.singGreen.opacity(0.15), in: Capsule()).foregroundStyle(Color.singGreen) }
                    }
                    Text(planSubtitle(p)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(p.displayPrice + periodSuffix(p)).font(.subheadline.weight(.semibold)).monospacedDigit()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").foregroundStyle(isSelected ? Color.voice : .secondary)
            }
            .padding(14)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isSelected ? Color.voice : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func planTitle(_ p: Product) -> String {
        switch p.id {
        case ProductID.monthly: return "Monthly"
        case ProductID.yearly: return "Yearly"
        default: return "Lifetime"
        }
    }

    private func planSubtitle(_ p: Product) -> String {
        if let trial = store.trialLabel(for: p) { return "\(trial), cancel any time" }
        return p.id == ProductID.lifetime ? "Pay once, keep forever" : "Cancel any time"
    }
}
