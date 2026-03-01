//
//  ContentView.swift
//  PoL
//
//  Created by Peiqi Tang on 2/12/26.
//

import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    private enum AppTab: Hashable {
        case summary
        case settings
        case activities
    }

    @EnvironmentObject private var wearablesManager: WearablesManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \ActivityEventRecord.timestamp, order: .reverse) private var timelineEvents: [ActivityEventRecord]
    @State private var selectedTab: AppTab = .summary
    @State private var eventPendingEdit: ActivityEventRecord?
    @State private var eventPendingDelete: ActivityEventRecord?
    @State private var timelineActionError: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                Form {
                    Section {
                        Text("Summary dashboard is coming next.")
                            .foregroundStyle(.secondary)
                    }

                    Section("Quick Stats") {
                        let visibleEvents = timelineEvents.filter { !$0.isDeleted }
                        statusRow("Total Events", "\(visibleEvents.count)")
                        statusRow("Stream State", wearablesManager.streamStateText)
                    }
                }
                .navigationTitle("Summary")
            }
            .tabItem {
                Label("Summary", systemImage: "chart.bar")
            }
            .tag(AppTab.summary)

            NavigationStack {
                Form {
                    Section {
                        statusRow("Stream State", wearablesManager.streamStateText)

                        if wearablesManager.hasActiveStreamSession {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "hand.tap.fill")
                                    .foregroundStyle(.blue)
                                Text("Tap once on the glasses touch pad when you are ready to log the activity, tap again to finish logging.")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            .padding(10)
                            .background(.blue.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            Button("Cancel Session (Discard Capture)", role: .destructive) {
                                Task {
                                    await wearablesManager.cancelCurrentSession()
                                }
                            }
                        }
                    }

                    let visibleEvents = timelineEvents.filter { !$0.isDeleted }
                    if visibleEvents.isEmpty {
                        Section("Activity Timeline") {
                            Text("No activity events yet. End a segment to create one.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        let calendar = Calendar.current
                        let groupedEvents = Dictionary(grouping: visibleEvents) {
                            calendar.startOfDay(for: $0.timestamp)
                        }
                        let sortedDays = groupedEvents.keys.sorted(by: >)

                        ForEach(sortedDays, id: \.self) { day in
                            Section(day.formatted(date: .abbreviated, time: .omitted)) {
                                let eventsForDay = (groupedEvents[day] ?? []).sorted {
                                    $0.timestamp > $1.timestamp
                                }
                                ForEach(eventsForDay) { event in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        HStack {
                                            Text(event.label.displayName)
                                                .font(.headline)
                                            if event.needsReview {
                                                Text("Needs Review")
                                                    .font(.caption)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(.yellow.opacity(0.2))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        Text(event.rationaleShort)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("Confidence: \(event.confidence.formatted(.number.precision(.fractionLength(2))))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button {
                                            eventPendingDelete = event
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .tint(.red)

                                        Button {
                                            eventPendingEdit = event
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(activitiesBackground)
                .navigationTitle("Activities")
            }
            .tabItem {
                Label("Activities", systemImage: "list.bullet.rectangle")
            }
            .tag(AppTab.activities)

            NavigationStack {
                Form {
                    if let error = wearablesManager.lastError {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }

                    if !wearablesManager.isDeviceRegistered {
                        Section {
                            widgetRow {
                                registrationButton(isRegistered: false)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowBackground(Color.clear)
                        }
                    }

                    if wearablesManager.isDeviceRegistered && !wearablesManager.isCameraPermissionGranted {
                        Section {
                            widgetRow {
                                actionCardButton(
                                    title: "Request Camera Permission",
                                    color: Color(red: 0, green: 0.73, blue: 1),
                                    shadowColor: Color(red: 0.19, green: 0.51, blue: 0.63).opacity(0.5)
                                ) {
                                    Task {
                                        await wearablesManager.requestCameraPermission()
                                    }
                                }
                            }
                            .disabled(wearablesManager.isBusy)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                        }
                    }

                    if wearablesManager.isDeviceRegistered && wearablesManager.isCameraPermissionGranted {
                        widgetRow {
                            cameraStreamCard
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                    }

                    Section("Diagnostics") {
                        widgetRow {
                            widgetCard {
                                VStack(spacing: 0) {
                                    statusRow("Camera Permission", wearablesManager.cameraPermissionText)
                                        .padding(.vertical, 12)
                                    Divider()
                                    NavigationLink("Debug Logs") {
                                        DebugLogsView()
                                    }
                                    .padding(.vertical, 12)
                                    Divider()
                                    NavigationLink("Live Preview") {
                                        LivePreviewView()
                                    }
                                    .padding(.vertical, 12)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                    }

                    if wearablesManager.isDeviceRegistered {
                        Section {
                            widgetRow {
                                registrationButton(isRegistered: true)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                .safeAreaInset(edge: .top) {
                    Color.clear.frame(height: 8)
                }
                .listSectionSpacing(.compact)
                .scrollContentBackground(.hidden)
                .background(settingsBackground)
                .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .onChange(of: selectedTab) { _, newValue in
            wearablesManager.setActivitiesTabActive(newValue == .activities)
            updateIdleTimerPolicy()
        }
        .onChange(of: scenePhase) { _, _ in
            updateIdleTimerPolicy()
        }
        .onChange(of: wearablesManager.streamStateText) { _, _ in
            updateIdleTimerPolicy()
        }
        .task {
            wearablesManager.configurePipelineIfNeeded(modelContext: modelContext)
            wearablesManager.setActivitiesTabActive(selectedTab == .activities)
            updateIdleTimerPolicy()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(
            isPresented: Binding(
                get: { eventPendingEdit != nil },
                set: { isPresented in
                    if !isPresented { eventPendingEdit = nil }
                }
            )
        ) {
            NavigationStack {
                List {
                    if let event = eventPendingEdit {
                        Section("Current") {
                            Text(event.label.displayName)
                                .font(.headline)
                        }
                    }

                    Section("Change To") {
                        ForEach(editableActivityLabels, id: \.self) { label in
                            Button {
                                if let event = eventPendingEdit {
                                    updateActivityType(for: event, to: label)
                                }
                                eventPendingEdit = nil
                            } label: {
                                Text(label.displayName)
                            }
                        }
                    }
                }
                .navigationTitle("Edit Activity Type")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            eventPendingEdit = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(
            "Delete Activity?",
            isPresented: Binding(
                get: { eventPendingDelete != nil },
                set: { isPresented in
                    if !isPresented { eventPendingDelete = nil }
                }
            ),
            presenting: eventPendingDelete
        ) { event in
            Button("Delete", role: .destructive) {
                deleteActivity(event)
            }
            Button("Cancel", role: .cancel) {
                eventPendingDelete = nil
            }
        } message: { _ in
            Text("This activity will be removed from the timeline.")
        }
        .alert(
            "Timeline Update Failed",
            isPresented: Binding(
                get: { timelineActionError != nil },
                set: { isPresented in
                    if !isPresented { timelineActionError = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                timelineActionError = nil
            }
        } message: {
            Text(timelineActionError ?? "Please try again.")
        }
    }

    @ViewBuilder
    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func statusTwoLineRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
            Text(value)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func widgetRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private enum CameraStreamLayoutState {
        case stopped
        case streaming
        case paused
    }

    private var editableActivityLabels: [ActivityLabel] {
        [.diaperWet, .diaperBowel, .feeding, .sleepStart, .wakeUp]
    }

    private func updateActivityType(for event: ActivityEventRecord, to newLabel: ActivityLabel) {
        event.label = newLabel
        event.isUserCorrected = true
        event.needsReview = false
        persistTimelineChanges()
    }

    private func deleteActivity(_ event: ActivityEventRecord) {
        event.isDeleted = true
        persistTimelineChanges()
        eventPendingDelete = nil
    }

    private func persistTimelineChanges() {
        do {
            try modelContext.save()
        } catch {
            timelineActionError = error.localizedDescription
        }
    }

    private var settingsBackground: some View {
        Group {
            if let imagePath = Bundle.main.path(forResource: "SettingsBackground", ofType: "jpg"),
               let image = UIImage(contentsOfFile: imagePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("SettingsBackground")
                    .resizable()
                    .scaledToFill()
            }
        }
        .ignoresSafeArea()
    }

    private var activitiesBackground: some View {
        Group {
            if let imagePath = Bundle.main.path(forResource: "Activities background", ofType: "jpg"),
               let image = UIImage(contentsOfFile: imagePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("Activities background")
                    .resizable()
                    .scaledToFill()
            }
        }
        .ignoresSafeArea()
    }

    private var streamLayoutState: CameraStreamLayoutState {
        let normalized = wearablesManager.streamStateText
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        if normalized.contains("paused") {
            return .paused
        }
        if normalized.contains("streaming")
            || normalized.contains("starting")
            || normalized.contains("waitingfordevice")
            || normalized.contains("connecting") {
            return .streaming
        }
        return .stopped
    }

    @ViewBuilder
    private func registrationButton(isRegistered: Bool) -> some View {
        let borderColor: Color = isRegistered ? .red : Color(red: 0, green: 0.73, blue: 1)
        let shadowColor = (isRegistered ? Color.red : Color(red: 0.19, green: 0.51, blue: 0.63)).opacity(0.5)
        actionCardButton(
            title: isRegistered ? "Unregister Your Glasses" : "Register your glasses",
            color: borderColor,
            shadowColor: shadowColor
        ) {
            Task {
                if isRegistered {
                    await wearablesManager.startUnregistration()
                } else {
                    await wearablesManager.startRegistration()
                }
            }
        }
        .disabled(wearablesManager.isBusy)
    }

    @ViewBuilder
    private func actionCardButton(
        title: String,
        color: Color,
        shadowColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(shadowColor)
                    .offset(y: 4)

                RoundedRectangle(cornerRadius: 24)
                    .fill(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(color, lineWidth: 1)
                    )

                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
        }
    }

    @ViewBuilder
    private func widgetCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(red: 0.19, green: 0.51, blue: 0.63).opacity(0.5))
                .offset(y: 4)

            RoundedRectangle(cornerRadius: 24)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color(red: 0.93, green: 0.93, blue: 0.93), lineWidth: 1)
                )

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cameraStreamCard: some View {
        let statusText: String = {
            switch streamLayoutState {
            case .stopped:
                return "Stopped"
            case .streaming:
                return "Streaming"
            case .paused:
                return "Paused"
            }
        }()

        let banner: (text: String, color: Color)? = {
            switch streamLayoutState {
            case .stopped:
                return nil
            case .streaming:
                return (
                    "To get ready for the experience, tap once on the glasses touch pad to pause the streaming, then switch to the Activities tab.",
                    Color(red: 1.0, green: 0.60, blue: 0.24)
                )
            case .paused:
                return (
                    "Great! Head over to the Activities tab and try out the experience!",
                    Color(red: 0.09, green: 0.67, blue: 0.34)
                )
            }
        }()

        return VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.19, green: 0.51, blue: 0.63).opacity(0.5))
                    .offset(y: 4)

                RoundedRectangle(cornerRadius: 24)
                    .fill(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color(red: 0.93, green: 0.93, blue: 0.93), lineWidth: 1)
                    )

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Camera Stream")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.black)
                        Text(statusText)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.gray)
                    }
                    Spacer(minLength: 12)
                    controlButton(for: streamLayoutState)
                    stopButton(for: streamLayoutState)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .frame(height: 96)

            if let banner {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(red: 0.19, green: 0.51, blue: 0.63).opacity(0.5))
                        .offset(y: 4)

                    RoundedRectangle(cornerRadius: 24)
                        .fill(banner.color)

                    Text(banner.text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func controlButton(for state: CameraStreamLayoutState) -> some View {
        switch state {
        case .stopped:
            Button {
                Task {
                    await wearablesManager.startCameraStream()
                }
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color(red: 0.10, green: 0.67, blue: 0.90)))
            }
            .disabled(wearablesManager.isBusy || wearablesManager.hasActiveStreamSession)
        case .streaming:
            ZStack {
                Circle()
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
                    .frame(width: 64, height: 64)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.96, green: 0.96, blue: 0.96))
                        .frame(width: 8, height: 30)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.96, green: 0.96, blue: 0.96))
                        .frame(width: 8, height: 30)
                }
            }
        case .paused:
            ZStack {
                Circle()
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
                    .frame(width: 64, height: 64)
                Image(systemName: "play.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.96))
            }
        }
    }

    private func stopButton(for state: CameraStreamLayoutState) -> some View {
        let enabled = state != .stopped
        return Button {
            Task {
                await wearablesManager.stopCameraStream()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(enabled ? Color.red : Color(red: 0.85, green: 0.85, blue: 0.85))
                    .frame(width: 64, height: 64)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.96, green: 0.96, blue: 0.96))
                    .frame(width: 24, height: 24)
            }
        }
        .disabled(wearablesManager.isBusy || !enabled)
    }

    private func updateIdleTimerPolicy() {
        let shouldDisableIdleTimer = scenePhase == .active && wearablesManager.hasActiveStreamSession
        if UIApplication.shared.isIdleTimerDisabled != shouldDisableIdleTimer {
            UIApplication.shared.isIdleTimerDisabled = shouldDisableIdleTimer
        }
    }

}

private struct DebugLogsView: View {
    @EnvironmentObject private var wearablesManager: WearablesManager

    var body: some View {
        Form {
            Section("Debug Logs") {
                HStack {
                    Text("Button-Like Event")
                    Spacer()
                    Text(wearablesManager.buttonLikeEventDetected ? "detected" : "not detected")
                        .foregroundStyle(.secondary)
                }

                Button("Mark Manual Glasses Press") {
                    wearablesManager.markManualButtonPress()
                }

                Button("Clear Logs", role: .destructive) {
                    wearablesManager.clearDebugEvents()
                }
            }

            Section("Event List") {
                if wearablesManager.debugEvents.isEmpty {
                    Text("No wearable events logged yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(wearablesManager.debugEvents) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(event.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if event.isManualMarker {
                                    Text("Manual Marker")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.15))
                                        .clipShape(Capsule())
                                } else if event.isButtonLike {
                                    Text("Button-Like")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.orange.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !event.metadata.isEmpty {
                                Text(formatDebugMetadata(event.metadata))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Debug Logs")
    }

    private func formatDebugMetadata(_ metadata: [String: String]) -> String {
        metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }
}

private struct LivePreviewView: View {
    @EnvironmentObject private var wearablesManager: WearablesManager

    var body: some View {
        Group {
            if let frame = wearablesManager.latestFrame {
                ScrollView {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding()
                }
            } else {
                ContentUnavailableView(
                    "No Live Preview Yet",
                    systemImage: "video.slash",
                    description: Text("Start streaming to load live frames.")
                )
            }
        }
        .navigationTitle("Live Preview")
    }
}

#Preview {
    ContentView()
        .environmentObject(WearablesManager(autoConfigure: false))
        .modelContainer(for: ActivityEventRecord.self, inMemory: true)
}
