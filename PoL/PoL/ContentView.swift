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
    @State private var eventPendingValueEdit: ActivityValueEditor?
    @State private var feedingAmountDraft: String = ""
    @State private var diaperChangeValueDraft: DiaperChangeValue = .wet
    @State private var timeDraft: Date = .now
    @State private var timelineActionError: String?
    @State private var isFeedingGraphEnabled = true
    @State private var isDiaperGraphEnabled = true
    @State private var isSleepGraphEnabled = true

    private struct ActivityValueEditor: Identifiable {
        enum Mode: String {
            case feedingAmount
            case diaperChangeValue
            case time
        }

        let event: ActivityEventRecord
        let mode: Mode

        var id: String {
            "\(event.id.uuidString)-\(mode.rawValue)"
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                Form {
                    Section {
                        widgetRow {
                            summaryLastActivitiesCard
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)

                        widgetRow {
                            summaryActivityGraphCard
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }
                .safeAreaInset(edge: .top) {
                    Color.clear.frame(height: 8)
                }
                .scrollContentBackground(.hidden)
                .background(summaryBackground)
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
                                    activityTimelineCard(for: event)
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
                .safeAreaInset(edge: .top) {
                    Color.clear.frame(height: 8)
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
                                    title: "Request camera permission",
                                    textColor: Color(red: 0.0, green: 0.25, blue: 0.35),
                                    borderColor: Color(red: 0.0, green: 0.25, blue: 0.35)
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
        .sheet(item: $eventPendingValueEdit) { editor in
            NavigationStack {
                Form {
                    switch editor.mode {
                    case .feedingAmount:
                        Section("Amount (oz)") {
                            TextField("0.0", text: $feedingAmountDraft)
                                .keyboardType(.decimalPad)
                        }
                        Section {
                            Button("Clear Amount", role: .destructive) {
                                feedingAmountDraft = ""
                            }
                        }
                    case .diaperChangeValue:
                        Section("Value") {
                            Picker("Value", selection: $diaperChangeValueDraft) {
                                ForEach(DiaperChangeValue.allCases) { value in
                                    Text(value.displayName).tag(value)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    case .time:
                        Section("Time") {
                            DatePicker(
                                "Event Time",
                                selection: $timeDraft,
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                        }
                    }
                }
                .navigationTitle(valueEditorTitle(for: editor.mode))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            eventPendingValueEdit = nil
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            applyValueEdit(editor)
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

    private var summaryLastActivitiesCard: some View {
        let visibleEvents = timelineEvents.filter { !$0.isDeleted }
        let latestDiaperEvent = visibleEvents.first {
            $0.label == .diaperWet || $0.label == .diaperBowel || $0.diaperChangeValue != nil
        }
        let latestSleepStartTimestamp = latestActivityTimestamp(in: visibleEvents) { $0.label == .sleepStart }
        let latestWakeUpTimestamp = latestActivityTimestamp(in: visibleEvents) { $0.label == .wakeUp }
        let isCurrentlyAsleep: Bool = {
            guard let latestSleepStartTimestamp else { return false }
            guard let latestWakeUpTimestamp else { return true }
            return latestSleepStartTimestamp > latestWakeUpTimestamp
        }()
        let thirdRowTitle = isCurrentlyAsleep ? "Asleep" : "Awake"
        let thirdRowTimestamp = isCurrentlyAsleep ? latestSleepStartTimestamp : latestWakeUpTimestamp

        let diaperTitle: String = {
            guard let latestDiaperEvent else { return "Diaper Change" }
            switch resolvedDiaperChangeValue(for: latestDiaperEvent) {
            case .wet:
                return "Diaper Change (Wet)"
            case .bm:
                return "Diaper Change (BM)"
            case .dry:
                return "Diaper Change (Dry)"
            }
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)

            VStack(alignment: .leading, spacing: 12) {
                summaryElapsedTimeRow(
                    title: "Last Feeding",
                    titleColor: Color(red: 0.52, green: 0.18, blue: 0.56),
                    timeColor: Color(red: 0.52, green: 0.18, blue: 0.56),
                    mode: .ago,
                    timestamp: latestActivityTimestamp(in: visibleEvents) { $0.label == .feeding }
                )
                Divider()
                summaryElapsedTimeRow(
                    title: diaperTitle,
                    titleColor: Color(red: 0.53, green: 0.46, blue: 0.03),
                    timeColor: Color(red: 0.53, green: 0.46, blue: 0.03),
                    mode: .ago,
                    timestamp: latestDiaperEvent?.timestamp
                )
                Divider()
                summaryElapsedTimeRow(
                    title: thirdRowTitle,
                    titleColor: Color(red: 0.00, green: 0.47, blue: 0.62),
                    timeColor: Color(red: 0.00, green: 0.47, blue: 0.62),
                    mode: .forNow,
                    timestamp: thirdRowTimestamp
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private enum SummaryElapsedRowMode {
        case ago
        case forNow
    }

    private struct SummaryGraphDayGroup: Identifiable {
        let start: Date
        let end: Date
        let displayDate: Date

        var id: Date { start }
    }

    private var summaryActivityGraphCard: some View {
        let visibleEvents = timelineEvents.filter { !$0.isDeleted }
        let dayGroups = summaryGraphDayGroups(from: visibleEvents)
        let sleepIntervals = resolvedSleepIntervals(from: visibleEvents)

        return widgetCard {
            VStack(alignment: .leading, spacing: 14) {
                summaryActivityGraph(
                    dayGroups: dayGroups,
                    events: visibleEvents,
                    sleepIntervals: sleepIntervals
                )

                HStack(spacing: 12) {
                    summaryToggleButton(
                        title: "Feeding",
                        color: Color(red: 0.52, green: 0.18, blue: 0.56),
                        isOn: isFeedingGraphEnabled
                    ) {
                        isFeedingGraphEnabled.toggle()
                    }
                    summaryToggleButton(
                        title: "Diaper",
                        color: Color(red: 0.53, green: 0.46, blue: 0.03),
                        isOn: isDiaperGraphEnabled
                    ) {
                        isDiaperGraphEnabled.toggle()
                    }
                    summaryToggleButton(
                        title: "Sleep",
                        color: Color(red: 0.00, green: 0.47, blue: 0.62),
                        isOn: isSleepGraphEnabled
                    ) {
                        isSleepGraphEnabled.toggle()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var summaryGraphTimeMarkers: [(label: String, hour: Double)] {
        [
            ("8 AM", 8),
            ("Noon", 12),
            ("4 PM", 16),
            ("8 PM", 20),
            ("12 AM", 24),
            ("4 AM", 28),
            ("8 AM", 32)
        ]
    }

    private func summaryActivityGraph(
        dayGroups: [SummaryGraphDayGroup],
        events: [ActivityEventRecord],
        sleepIntervals: [(start: Date, end: Date)]
    ) -> some View {
        let dayColumnWidth: CGFloat = 58
        let daySpacing: CGFloat = 8
        let labelWidth: CGFloat = 36
        let chartHeight: CGFloat = 286
        let topAxisHeight: CGFloat = 34
        let filteredEvents = events.filter { event in
            if event.label == .feeding {
                return isFeedingGraphEnabled
            }
            if event.label == .diaperWet || event.label == .diaperBowel || event.diaperChangeValue != nil {
                return isDiaperGraphEnabled
            }
            return false
        }

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                Color.clear
                    .frame(height: topAxisHeight)
                ZStack(alignment: .topTrailing) {
                    ForEach(summaryGraphTimeMarkers, id: \.hour) { marker in
                        Text(marker.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.65))
                            .offset(y: yPosition(forHour: marker.hour, chartHeight: chartHeight) - 8)
                    }
                }
                .frame(width: labelWidth, height: chartHeight, alignment: .topTrailing)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: daySpacing) {
                    ForEach(dayGroups) { group in
                        VStack(spacing: 8) {
                            dayPill(for: group.displayDate)
                            dayTimelineColumn(
                                dayGroup: group,
                                events: filteredEvents,
                                sleepIntervals: sleepIntervals,
                                width: dayColumnWidth,
                                height: chartHeight
                            )
                        }
                        .frame(width: dayColumnWidth)
                    }
                }
                .padding(.trailing, 4)
            }
        }
    }

    private func dayPill(for day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        return ZStack {
            Circle()
                .fill(isToday ? .black : Color(red: 0.88, green: 0.88, blue: 0.88))
            Text(weekdayLetter(for: day))
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(isToday ? .white : .black.opacity(0.8))
        }
        .frame(width: 52, height: 52)
    }

    private func dayTimelineColumn(
        dayGroup: SummaryGraphDayGroup,
        events: [ActivityEventRecord],
        sleepIntervals: [(start: Date, end: Date)],
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let window = graphWindow(for: dayGroup.displayDate)
        let dayEvents = events.filter { event in
            event.timestamp >= dayGroup.start && event.timestamp < dayGroup.end
        }
        let feedingEvents = dayEvents.filter { $0.label == .feeding }
        let diaperEvents = dayEvents.filter {
            $0.label == .diaperWet || $0.label == .diaperBowel || $0.diaperChangeValue != nil
        }
        let daySleepSegments = sleepIntervals.compactMap { interval -> (start: Date, end: Date)? in
            let start = max(interval.start, dayGroup.start)
            let end = min(interval.end, dayGroup.end)
            return end > start ? (start, end) : nil
        }

        return ZStack(alignment: .topLeading) {
            ForEach(summaryGraphTimeMarkers, id: \.hour) { marker in
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(height: 1)
                    .offset(y: yPosition(forHour: marker.hour, chartHeight: height))
            }

            if isFeedingGraphEnabled {
                ForEach(feedingEvents, id: \.id) { event in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.52, green: 0.18, blue: 0.56))
                        .frame(width: width - 8, height: 8)
                        .offset(x: 4, y: yPosition(for: event.timestamp, in: window.start, chartHeight: height) - 4)
                }
            }

            if isDiaperGraphEnabled {
                ForEach(diaperEvents, id: \.id) { event in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.53, green: 0.46, blue: 0.03))
                        .frame(width: width - 8, height: 8)
                        .offset(x: 4, y: yPosition(for: event.timestamp, in: window.start, chartHeight: height) - 4)
                }
            }

            if isSleepGraphEnabled {
                ForEach(Array(daySleepSegments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.00, green: 0.47, blue: 0.62))
                        .frame(
                            width: width - 8,
                            height: max(
                                8,
                                yPosition(for: segment.end, in: window.start, chartHeight: height)
                                - yPosition(for: segment.start, in: window.start, chartHeight: height)
                            )
                        )
                        .offset(
                            x: 4,
                            y: yPosition(for: segment.start, in: window.start, chartHeight: height)
                        )
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private func summaryToggleButton(
        title: String,
        color: Color,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isOn ? .white : color)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(height: 38)
                .background(
                    Capsule()
                        .fill(isOn ? color : .white)
                        .overlay(
                            Capsule()
                                .strokeBorder(color, lineWidth: 2)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func summaryGraphDayGroups(from events: [ActivityEventRecord]) -> [SummaryGraphDayGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        if events.isEmpty {
            return (0..<7).compactMap { offset in
                guard let displayDate = calendar.date(byAdding: .day, value: -offset, to: today) else {
                    return nil
                }
                let window = graphWindow(for: displayDate)
                return SummaryGraphDayGroup(
                    start: window.start,
                    end: window.end,
                    displayDate: displayDate
                )
            }
        }

        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var dayStartMarkers: [Date] = [sorted[0].timestamp]
        var nightSleepOpen = false
        var pendingNightWake: Date?

        for event in sorted {
            if event.label == .sleepStart, isNightSleepStart(event.timestamp) {
                nightSleepOpen = true
                pendingNightWake = nil
                continue
            }

            if event.label == .wakeUp, nightSleepOpen {
                pendingNightWake = event.timestamp
                nightSleepOpen = false
                continue
            }

            let isNonSleepActivity = event.label != .sleepStart && event.label != .wakeUp
            if isNonSleepActivity, let activePendingNightWake = pendingNightWake, event.timestamp > activePendingNightWake {
                if let last = dayStartMarkers.last, event.timestamp > last {
                    dayStartMarkers.append(event.timestamp)
                }
                pendingNightWake = nil
            }
        }

        let timelineEnd = max(sorted.last?.timestamp ?? .now, .now)
        var groups: [SummaryGraphDayGroup] = []

        for index in dayStartMarkers.indices {
            let start = dayStartMarkers[index]
            let end = index + 1 < dayStartMarkers.count
                ? dayStartMarkers[index + 1]
                : timelineEnd.addingTimeInterval(1)
            groups.append(
                SummaryGraphDayGroup(
                    start: start,
                    end: end,
                    displayDate: calendar.startOfDay(for: start)
                )
            )
        }

        var newestFirst = Array(groups.reversed())
        while newestFirst.count < 7 {
            let referenceDate = newestFirst.last?.displayDate ?? today
            guard let previousDate = calendar.date(byAdding: .day, value: -1, to: referenceDate) else { break }
            let window = graphWindow(for: previousDate)
            newestFirst.append(
                SummaryGraphDayGroup(
                    start: window.start,
                    end: window.end,
                    displayDate: previousDate
                )
            )
        }

        return Array(newestFirst.prefix(21))
    }

    private func isNightSleepStart(_ timestamp: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: timestamp)
        return hour >= 19 || hour < 7
    }

    private func resolvedSleepIntervals(from events: [ActivityEventRecord]) -> [(start: Date, end: Date)] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var intervals: [(start: Date, end: Date)] = []
        var openSleepStart: Date?

        for event in sorted {
            if event.label == .sleepStart {
                openSleepStart = event.timestamp
            } else if event.label == .wakeUp, let activeSleepStart = openSleepStart, event.timestamp > activeSleepStart {
                intervals.append((start: activeSleepStart, end: event.timestamp))
                openSleepStart = nil
            }
        }

        if let openSleepStart {
            intervals.append((start: openSleepStart, end: .now))
        }

        return intervals
    }

    private func graphWindow(for day: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let windowStart = calendar.date(byAdding: .hour, value: 8, to: dayStart) ?? dayStart
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: windowStart) ?? windowStart
        return (start: windowStart, end: windowEnd)
    }

    private func yPosition(for timestamp: Date, in dayWindowStart: Date, chartHeight: CGFloat) -> CGFloat {
        let elapsedHours = max(0, min(24, timestamp.timeIntervalSince(dayWindowStart) / 3600))
        return CGFloat(elapsedHours / 24) * chartHeight
    }

    private func yPosition(forHour hour: Double, chartHeight: CGFloat) -> CGFloat {
        let normalized = max(8, min(32, hour))
        return CGFloat((normalized - 8) / 24.0) * chartHeight
    }

    private func weekdayLetter(for day: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: day)
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        return letters[max(0, min(letters.count - 1, weekday - 1))]
    }

    @ViewBuilder
    private func summaryElapsedTimeRow(
        title: String,
        titleColor: Color,
        timeColor: Color,
        mode: SummaryElapsedRowMode,
        timestamp: Date?
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(titleColor)
            Spacer()
            summaryElapsedTimeValueText(
                timestamp: timestamp,
                timeColor: timeColor,
                mode: mode
            )
            .multilineTextAlignment(.trailing)
        }
    }

    private func latestActivityTimestamp(
        in events: [ActivityEventRecord],
        where predicate: (ActivityEventRecord) -> Bool
    ) -> Date? {
        events.first(where: predicate)?.timestamp
    }

    private func summaryElapsedTimeValueText(
        timestamp: Date?,
        timeColor: Color,
        mode: SummaryElapsedRowMode
    ) -> Text {
        guard let timestamp else {
            return Text("No record")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.gray)
        }

        let elapsedTime = elapsedTimeHoursMinutesText(since: timestamp)
        let prefixText = Text("for ")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.gray)
        let suffixAgoText = Text(" ago")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.gray)
        let suffixNowText = Text(" now")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.gray)
        let emphasizedTime = Text(elapsedTime)
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(timeColor)

        switch mode {
        case .ago:
            return Text("\(emphasizedTime)\(suffixAgoText)")
        case .forNow:
            return Text("\(prefixText)\(emphasizedTime)\(suffixNowText)")
        }
    }

    private func elapsedTimeHoursMinutesText(since timestamp: Date?) -> String {
        guard let timestamp else { return "0h00m" }
        let seconds = max(0, Int(Date().timeIntervalSince(timestamp)))
        let totalHours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return "\(totalHours)h\(String(format: "%02d", minutes))m"
    }

    private enum CameraStreamLayoutState {
        case stopped
        case streaming
        case paused
    }

    private var editableActivityLabels: [ActivityLabel] {
        [.diaperWet, .diaperBowel, .feeding, .sleepStart, .wakeUp]
    }

    @ViewBuilder
    private func activityTimelineCard(for event: ActivityEventRecord) -> some View {
        widgetCard {
            if event.label == .other {
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(.black)
                            .frame(width: 3, height: 18)
                        Text("Other")
                            .font(.headline)
                            .foregroundStyle(.black)
                    }

                    Text(event.rationaleShort)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text("Confidence: \(event.confidence.formatted(.number.precision(.fractionLength(2))))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if event.needsReview {
                            Text("Needs Review")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.yellow.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(activityCardTitle(for: event))
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

                    switch valueEditorMode(for: event) {
                    case .feedingAmount?:
                        cardValueButton(
                            label: "Amount",
                            value: feedingAmountDisplayText(for: event),
                            emphasize: event.feedingAmountOz == nil
                        ) {
                            presentFeedingAmountEditor(for: event)
                        }
                    case .diaperChangeValue?:
                        cardValueButton(
                            label: "Value",
                            value: resolvedDiaperChangeValue(for: event).displayName
                        ) {
                            presentDiaperChangeEditor(for: event)
                        }
                    case .time?:
                        cardValueButton(
                            label: "Time",
                            value: event.timestamp.formatted(date: .omitted, time: .shortened)
                        ) {
                            presentTimeEditor(for: event)
                        }
                    case nil:
                        EmptyView()
                    }

                    Text(event.rationaleShort)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Text("Confidence: \(event.confidence.formatted(.number.precision(.fractionLength(2))))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func cardValueButton(
        label: String,
        value: String,
        emphasize: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(emphasize ? .blue : .primary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(red: 0.96, green: 0.98, blue: 0.99))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func valueEditorTitle(for mode: ActivityValueEditor.Mode) -> String {
        switch mode {
        case .feedingAmount:
            return "Edit Amount"
        case .diaperChangeValue:
            return "Edit Value"
        case .time:
            return "Edit Time"
        }
    }

    private func valueEditorMode(for event: ActivityEventRecord) -> ActivityValueEditor.Mode? {
        if event.label == .feeding {
            return .feedingAmount
        }
        if isDiaperEvent(event) {
            return .diaperChangeValue
        }
        if event.label == .sleepStart || event.label == .wakeUp {
            return .time
        }
        return nil
    }

    private func activityCardTitle(for event: ActivityEventRecord) -> String {
        if event.label == .feeding {
            return "Feeding"
        }
        if isDiaperEvent(event) {
            return "Diaper Change"
        }
        if event.label == .sleepStart {
            return "Fall Asleep"
        }
        if event.label == .wakeUp {
            return "Wake Up"
        }
        return event.label.displayName
    }

    private func isDiaperEvent(_ event: ActivityEventRecord) -> Bool {
        event.label == .diaperWet || event.label == .diaperBowel || event.diaperChangeValue != nil
    }

    private func feedingAmountDisplayText(for event: ActivityEventRecord) -> String {
        if let amount = event.feedingAmountOz {
            return "\(amount.formatted(.number.precision(.fractionLength(1)))) oz"
        }
        if let inferredAmount = event.inferredFeedingAmountOz {
            return "\(inferredAmount.formatted(.number.precision(.fractionLength(1)))) oz (Inferred)"
        }
        return "Enter amount"
    }

    private func resolvedDiaperChangeValue(for event: ActivityEventRecord) -> DiaperChangeValue {
        if let value = event.diaperChangeValue {
            return value
        }
        switch event.label {
        case .diaperWet:
            return .wet
        case .diaperBowel:
            return .bm
        default:
            return .dry
        }
    }

    private func presentFeedingAmountEditor(for event: ActivityEventRecord) {
        if let currentAmount = event.feedingAmountOz {
            feedingAmountDraft = currentAmount.formatted(.number.precision(.fractionLength(1)))
        } else if let inferredAmount = event.inferredFeedingAmountOz {
            feedingAmountDraft = inferredAmount.formatted(.number.precision(.fractionLength(1)))
        } else {
            feedingAmountDraft = ""
        }
        eventPendingValueEdit = ActivityValueEditor(event: event, mode: .feedingAmount)
    }

    private func presentDiaperChangeEditor(for event: ActivityEventRecord) {
        diaperChangeValueDraft = resolvedDiaperChangeValue(for: event)
        eventPendingValueEdit = ActivityValueEditor(event: event, mode: .diaperChangeValue)
    }

    private func presentTimeEditor(for event: ActivityEventRecord) {
        timeDraft = event.timestamp
        eventPendingValueEdit = ActivityValueEditor(event: event, mode: .time)
    }

    private func applyValueEdit(_ editor: ActivityValueEditor) {
        switch editor.mode {
        case .feedingAmount:
            let trimmed = feedingAmountDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                editor.event.feedingAmountOz = nil
            } else {
                guard let amount = Double(trimmed), amount >= 0 else {
                    timelineActionError = "Amount must be a number in oz, like 3.5."
                    return
                }
                editor.event.feedingAmountOz = (amount * 10).rounded() / 10
            }
            editor.event.isUserCorrected = true
            editor.event.needsReview = false
        case .diaperChangeValue:
            editor.event.diaperChangeValue = diaperChangeValueDraft
            switch diaperChangeValueDraft {
            case .wet:
                editor.event.label = .diaperWet
            case .bm:
                editor.event.label = .diaperBowel
            case .dry:
                editor.event.label = .other
            }
            editor.event.isUserCorrected = true
            editor.event.needsReview = false
        case .time:
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: timeDraft)
            if let hour = components.hour,
               let minute = components.minute,
               let updated = calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: editor.event.timestamp
               ) {
                editor.event.timestamp = updated
            } else {
                timelineActionError = "Failed to update time."
                return
            }
            editor.event.isUserCorrected = true
            editor.event.needsReview = false
        }

        persistTimelineChanges()
        eventPendingValueEdit = nil
    }

    private func updateActivityType(for event: ActivityEventRecord, to newLabel: ActivityLabel) {
        event.label = newLabel
        switch newLabel {
        case .diaperWet:
            event.diaperChangeValue = .wet
        case .diaperBowel:
            event.diaperChangeValue = .bm
        default:
            event.diaperChangeValue = nil
        }
        if newLabel != .feeding {
            event.feedingAmountOz = nil
            event.inferredFeedingAmountOz = nil
        }
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
        tabBackgroundImage(namedAnyOf: ["Settings background", "SettingsBackground"])
    }

    private var summaryBackground: some View {
        tabBackgroundImage(namedAnyOf: ["Summary background", "SummaryBackground"])
    }

    private var activitiesBackground: some View {
        tabBackgroundImage(namedAnyOf: ["Activities background", "Activity background", "ActivitiesBackground"])
    }

    private func tabBackgroundImage(namedAnyOf names: [String]) -> some View {
        Group {
            if let matchingName = names.first(where: { Bundle.main.path(forResource: $0, ofType: "jpg") != nil }),
               let imagePath = Bundle.main.path(forResource: matchingName, ofType: "jpg"),
               let image = UIImage(contentsOfFile: imagePath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(names.first ?? "")
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
        let figmaTextColor = Color(red: 0.0, green: 0.25, blue: 0.35)
        actionCardButton(
            title: isRegistered ? "Unregister your glasses" : "Register your glasses",
            textColor: figmaTextColor,
            borderColor: isRegistered ? nil : figmaTextColor
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
        textColor: Color,
        borderColor: Color?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.white)
                    .overlay(
                        Group {
                            if let borderColor {
                                RoundedRectangle(cornerRadius: 24)
                                    .strokeBorder(borderColor, lineWidth: 1)
                            }
                        }
                    )

                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(textColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
        }
    }

    @ViewBuilder
    private func widgetCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Color(red: 0.93, green: 0.93, blue: 0.93), lineWidth: 1)
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

        let stateContainerColor: Color? = {
            switch streamLayoutState {
            case .stopped:
                return nil
            case .streaming:
                return Color(red: 0.0, green: 0.25, blue: 0.35) // #004058
            case .paused:
                return Color(red: 0.25, green: 0.37, blue: 0.27) // #405e45
            }
        }()

        @ViewBuilder
        func topPanel() -> some View {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(Color(red: 0.93, green: 0.93, blue: 0.93), lineWidth: 1)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .frame(height: 96)
        }

        if let stateContainerColor {
            return AnyView(
                VStack(spacing: 0) {
                    topPanel()
                    Text(streamLayoutState == .streaming
                         ? "To get ready for the experience, tap once on the glasses touch pad to pause the streaming, then switch to the Activities tab."
                         : "Great! Head over to the Activities tab and try out the experience!")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .background(stateContainerColor)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .frame(maxWidth: .infinity, alignment: .leading)
            )
        } else {
            return AnyView(
                topPanel()
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        }
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
                    .background(Circle().fill(Color(red: 0.0, green: 0.25, blue: 0.35)))
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
                    .fill(enabled ? Color(red: 0.0, green: 0.25, blue: 0.35) : Color(red: 0.85, green: 0.85, blue: 0.85))
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
