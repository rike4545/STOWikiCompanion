import SwiftUI

struct CaptainCommandDashboard: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var companion = CompanionStore.shared
    @ObservedObject private var fleet = FleetOperationsStore.shared
    @ObservedObject private var economy = ProgressionEconomyStore.shared
    @ObservedObject private var advanced = AdvancedToolsStore.shared
    @State private var selectedCaptainID: UUID?

    private var selectedCaptain: CaptainProfile? {
        companion.captains.first { $0.id == selectedCaptainID } ?? companion.captains.first
    }

    private var activeCooldowns: [CooldownRecord] {
        fleet.cooldowns.filter { $0.readyAt > Date() }.sorted { $0.readyAt < $1.readyAt }
    }

    private var incompleteGoals: [ProgressRecord] { companion.progress.filter { !$0.isComplete } }
    private var activeCampaigns: [EventCampaignRecord] { advanced.campaigns.filter { $0.endDate >= Calendar.current.startOfDay(for: Date()) }.sorted { $0.endDate < $1.endDate } }
    private var inventoryShortfalls: [InventoryRecord] { fleet.inventory.filter { $0.targetQuantity > $0.quantity } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                captainCard
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metric("Saved loadouts", value: advanced.loadouts.count, icon: "ship", destination: "Advanced Loadouts")
                    metric("Open objectives", value: incompleteGoals.count, icon: "checklist", destination: "Progress")
                    metric("Inventory goals", value: inventoryShortfalls.count, icon: "shippingbox", destination: "Inventory")
                    metric("Active cooldowns", value: activeCooldowns.count, icon: "timer", destination: "Cooldowns")
                    metric("Fleet projects", value: economy.fleetProjects.count, icon: "building.2", destination: "Fleet Projects")
                    metric("Crafting plans", value: advanced.craftingPlans.count, icon: "hammer", destination: "Crafting")
                }

                sectionHeader("Next up", subtitle: "Your nearest timers and campaign deadlines")
                if activeCooldowns.isEmpty && activeCampaigns.isEmpty {
                    emptyRow("No upcoming timers or campaigns", icon: "calendar")
                }
                ForEach(activeCooldowns.prefix(3)) { item in
                    HStack {
                        Image(systemName: "timer").foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).foregroundStyle(.white)
                            Text(item.category).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.readyAt, style: .relative).font(.caption.monospacedDigit()).foregroundStyle(theme.secondaryAccent)
                    }.padding(12).background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                ForEach(activeCampaigns.prefix(3)) { item in
                    HStack {
                        Image(systemName: "flag.fill").foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).foregroundStyle(.white)
                            Text("\(item.completedDays) of \(item.requiredDays) participation days").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.endDate, style: .relative).font(.caption.monospacedDigit()).foregroundStyle(theme.secondaryAccent)
                    }.padding(12).background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
                }

                sectionHeader("Needs attention", subtitle: "Items with unfinished targets")
                ForEach(inventoryShortfalls.prefix(4)) { item in
                    HStack {
                        Text(item.name).foregroundStyle(.white)
                        Spacer()
                        Text("\(item.quantity) / \(item.targetQuantity)").font(.caption.monospacedDigit()).foregroundStyle(theme.secondaryAccent)
                    }.padding(10).background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
                }
                if !incompleteGoals.isEmpty {
                    ForEach(incompleteGoals.prefix(4)) { item in
                        HStack {
                            Image(systemName: "circle").foregroundStyle(theme.secondaryAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).foregroundStyle(.white)
                                Text(item.category).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(10).background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                sectionHeader("Quick launch", subtitle: "Jump straight into your command tools")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    quickLink("Build planner", icon: "wrench.and.screwdriver", destination: "Advanced Loadouts")
                    quickLink("Reputation", icon: "medal", destination: "Reputation")
                    quickLink("Exchange notebook", icon: "chart.line.uptrend.xyaxis", destination: "Exchange")
                    quickLink("Wiki catalog", icon: "books.vertical", destination: "Wiki Catalog")
                }
            }.padding(16)
        }
        .background(theme.background)
        .onChange(of: companion.captains) { _, captains in
            if !captains.contains(where: { $0.id == selectedCaptainID }) { selectedCaptainID = captains.first?.id }
        }
    }

    private var captainCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("STARFLEET COMMAND", systemImage: "command").font(.system(.caption, design: .monospaced, weight: .bold)).foregroundStyle(theme.secondaryAccent)
                Spacer()
                Text("PERSONAL OPERATIONS").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            }
            if companion.captains.isEmpty {
                Text("No captain selected").font(.title2.bold()).foregroundStyle(.white)
                Text("Create a captain profile to personalize this dashboard.").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Captain", selection: Binding(get: { selectedCaptain?.id }, set: { selectedCaptainID = $0 })) {
                    ForEach(companion.captains) { captain in Text(captain.name).tag(Optional(captain.id)) }
                }.pickerStyle(.menu).tint(theme.accent)
                if let captain = selectedCaptain {
                    Text("\(captain.faction) • \(captain.career)").font(.headline).foregroundStyle(.white)
                    Text(captain.specialization.isEmpty ? "Specialization not set" : captain.specialization).font(.caption).foregroundStyle(theme.secondaryAccent)
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.accent.opacity(0.45), lineWidth: 1))
    }

    private func metric(_ title: String, value: Int, icon: String, destination: String) -> some View {
        Button { NotificationCenter.default.post(name: .stowikiSelectCompanionSection, object: destination) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(theme.accent)
                Text(value.formatted()).font(.title2.bold().monospacedDigit()).foregroundStyle(.white)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 88, alignment: .leading).padding(12)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    private func quickLink(_ title: String, icon: String, destination: String) -> some View {
        Button { NotificationCenter.default.post(name: .stowikiSelectCompanionSection, object: destination) } label: {
            Label(title, systemImage: icon).font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading).padding(13)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).foregroundStyle(.white)
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline).foregroundStyle(.white)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }.padding(.top, 4)
    }

    private func emptyRow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}

extension Notification.Name {
    static let stowikiSelectCompanionSection = Notification.Name("stowiki.selectCompanionSection")
}
