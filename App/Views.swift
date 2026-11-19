import SwiftUI
import DrinkTrackerCore

private let accent = Color(red: 0.20, green: 0.52, blue: 0.43)

struct RootView: View {
    @Bindable var services: AppServices
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Screen", selection: $tab) {
                    Text("Tracking").tag(0); Text("History").tag(1)
                }.pickerStyle(.segmented).padding(.horizontal, 22).padding(.bottom, 20)
                if let error = services.storageError {
                    ContentUnavailableView("History unavailable", systemImage: "externaldrive.badge.exclamationmark",
                                           description: Text("Your saved files have been preserved. \(error)"))
                    Button("Try again") { Task { await services.refresh() } }.padding()
                } else if tab == 0 {
                    TrackingView(services: services)
                } else { HistoryView(services: services) }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Drink Tracker")
            .tint(accent)
            .alert("Couldn’t complete that action", isPresented: Binding(get: { services.actionError != nil }, set: { if !$0 { services.actionError = nil } })) {
                Button("OK", role: .cancel) { services.actionError = nil }
            } message: { Text(services.actionError ?? "") }
        }
        .task { await services.refresh() }
        .task(id: "\(scenePhase == .active)-\(services.days.first(where: { $0.state != .finalized })?.window.end.timeIntervalSince1970 ?? 0)") {
            guard scenePhase == .active,
                  let cutoff = services.days.first(where: { $0.state != .finalized })?.window.end else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, cutoff.timeIntervalSinceNow)))
                guard scenePhase == .active else { return }
                await services.refresh(observeDeadline: abs(Date().timeIntervalSince(cutoff)) < 2)
            } catch { /* Deadline observation was cancelled on a state/scene change. */ }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await services.refresh() } }
        }
        .onOpenURL { _ in tab = 0; Task { await services.refresh() } }
    }
}

struct TrackingView: View {
    @Bindable var services: AppServices
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(services.current.map { displayLabel($0) } ?? "Ready when you are")
                            .font(.title2.bold())
                        Text(services.current.map { "Finalizes \($0.window.end.formatted(date: .abbreviated, time: .shortened))" } ?? "Start a day to begin counting.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let current = services.current { StatusBadge(state: current.state) }
                }
                VStack(spacing: 0) {
                    ForEach(DrinkCategory.allCases) { category in
                        CounterRow(category: category, count: services.current?[category] ?? 0,
                                   enabled: services.current?.state == .active) { delta in
                            Task { await services.adjust(category, delta: delta) }
                        }
                        if category != .rageCage { Divider().padding(.leading, 20) }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 24))
                Button {
                    Task {
                        if let day = services.current {
                            if day.state == .active { await services.pause() } else { await services.resume() }
                        } else { await services.start() }
                    }
                } label: {
                    Label(buttonTitle, systemImage: services.current?.state == .active ? "pause.fill" : "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(services.busy)
                .accessibilityIdentifier("trackingAction")
                if let status = services.cardStatus, services.current?.state == .active {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(status, systemImage: "lock.rectangle").font(.footnote).foregroundStyle(.secondary)
                        Button("Show on Lock Screen") { Task { await services.restoreCard() } }
                            .buttonStyle(.bordered)
                    }
                }
                Text(services.current?.state == .paused ? "Your counts are saved. Resume any time before the cutoff." : "Three independent counts. Pause whenever you like.")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(22)
        }
    }
    private var buttonTitle: String {
        guard let current = services.current else { return "Start Tracking" }
        return current.state == .active ? "Pause" : "Resume"
    }
}

private struct CounterRow: View {
    let category: DrinkCategory
    let count: Int
    let enabled: Bool
    let action: (Int) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(category.emoji).font(.title2).accessibilityHidden(true)
                Text(category.title).font(.headline)
                Spacer(minLength: 4)
                Text(count.formatted()).font(.title2.bold()).monospacedDigit().minimumScaleFactor(0.7)
                    .accessibilityLabel("\(category.title), \(count)")
                    .accessibilityIdentifier("\(category.rawValue)-total")
            }
            HStack(spacing: 14) {
                TallyView(count: count, color: enabled ? accent : .secondary, height: 25)
                adjustment(-1); adjustment(1)
            }
        }
        .padding(20)
    }
    private func adjustment(_ delta: Int) -> some View {
        Button { action(delta) } label: {
            Image(systemName: delta == 1 ? "plus" : "minus")
                .font(.headline).frame(width: 46, height: 46)
                .background(accent.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain).foregroundStyle(accent)
        .disabled(!enabled || (delta == -1 && count == 0))
        .opacity(!enabled || (delta == -1 && count == 0) ? 0.35 : 1)
        .accessibilityLabel("\(delta == 1 ? "Add" : "Remove") \(category.unit)")
        .accessibilityIdentifier("\(category.rawValue)-\(delta == 1 ? "plus" : "minus")")
    }
}

struct HistoryView: View {
    let services: AppServices
    var body: some View {
        if services.days.isEmpty {
            ContentUnavailableView("Your days, kept here", systemImage: "calendar",
                                   description: Text("Days you start will appear here with totals and tracking times."))
        } else {
            List(services.days) { day in
                NavigationLink { DayDetailView(id: day.id, services: services) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(displayLabel(day)).font(.headline)
                            Spacer()
                            if day.effectiveState(at: Date()) != .finalized { StatusBadge(state: day.state) }
                        }
                        TotalsView(day: day)
                    }.padding(.vertical, 8)
                }
            }.listStyle(.insetGrouped).scrollContentBackground(.hidden)
        }
    }
}

struct DayDetailView: View {
    let id: UUID
    let services: AppServices
    var body: some View {
        if let day = services.days.first(where: { $0.id == id }) {
            List {
                Section("Daily totals") { TotalsView(day: day).padding(.vertical, 10) }
                Section("Tracking window") {
                    LabeledContent("From", value: windowDate(day.window.start, zone: day.window.timeZoneID))
                    LabeledContent("Until", value: windowDate(day.window.end, zone: day.window.timeZoneID))
                    LabeledContent("Time zone", value: day.window.timeZoneID)
                    LabeledContent("Duration", value: Duration.seconds(day.window.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    if day.window.basis == .fallback { Text("Time zone selected at Start Tracking.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Tracking activity") {
                    ForEach(day.events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(event.kind.rawValue.capitalized, systemImage: event.kind == .paused ? "pause.circle" : "play.circle")
                            Text(eventDate(event)).font(.footnote).foregroundStyle(.secondary)
                        }.padding(.vertical, 3)
                    }
                    if let finalized = day.finalizedAt {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Finalized automatically", systemImage: "checkmark.circle")
                            Text(finalized.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(displayLabel(day)).navigationBarTitleDisplayMode(.inline)
        }
    }
    private func windowDate(_ date: Date, zone: String) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        f.timeZone = TimeZone(identifier: zone)
        return f.string(from: date)
    }
    private func eventDate(_ event: EventSnapshot) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        f.timeZone = TimeZone(secondsFromGMT: event.utcOffset)
        return "\(f.string(from: event.occurredAt)) · \(event.timeZoneID)"
    }
}

private struct TotalsView: View {
    let day: DaySnapshot
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 22))
        layout {
            ForEach(DrinkCategory.allCases) { category in
                Text("\(category.emoji) \(day[category].formatted())").monospacedDigit()
                    .accessibilityLabel("\(category.title), \(day[category])")
            }
        }.font(.body.weight(.medium))
    }
}
private struct StatusBadge: View {
    let state: TrackingState
    var body: some View {
        Text(state.rawValue.capitalized).font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(accent.opacity(0.12), in: Capsule()).foregroundStyle(accent)
    }
}
private func displayLabel(_ day: DaySnapshot) -> String {
    let f = DateFormatter(); f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "EEE, MMM d, yyyy"
    return f.string(from: day.displayDate)
}
