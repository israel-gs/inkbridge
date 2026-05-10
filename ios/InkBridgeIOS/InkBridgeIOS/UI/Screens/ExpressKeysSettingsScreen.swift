import SwiftUI

// MARK: - ExpressKeysSettingsScreen

/// Settings screen for managing Express Key profiles and per-slot assignments.
///
/// # Layout
/// - Profile picker at top: scrollable list of profiles.
///   - Swipe-to-delete removes a profile (minimum 1 profile enforced).
///   - "+ New Profile" button at bottom of list.
///   - Tap a profile name to select it as active; double-tap to rename inline.
/// - Per-slot editor below: 6 rows (one per slot) with current key label + chevron.
///   - Tapping a row pushes `EditKeySheet` as a navigation destination.
///
/// # Data flow
/// - `ProfileStore` is injected and drives the profile list.
/// - `SettingsRepository` is injected for `activeProfileId` persistence.
public struct ExpressKeysSettingsScreen: View {

    // MARK: - State

    @State private var profiles: [ExpressKeyProfile]
    @State private var activeProfileId: UUID?
    @State private var editingSlotIndex: Int? = nil
    @State private var isShowingEditSheet: Bool = false
    @State private var renamingProfileId: UUID? = nil
    @State private var renameText: String = ""

    private let store: ProfileStore
    private let settingsRepo: any SettingsRepository

    // MARK: - Init

    public init(store: ProfileStore, settingsRepo: any SettingsRepository) {
        self.store = store
        self.settingsRepo = settingsRepo
        let loaded = store.loadProfiles()
        _profiles = State(initialValue: loaded)
        let idStr = settingsRepo.activeProfileId
        _activeProfileId = State(initialValue: UUID(uuidString: idStr) ?? loaded.first?.id)
    }

    // MARK: - Computed

    private var activeProfile: ExpressKeyProfile? {
        profiles.first { $0.id == activeProfileId } ?? profiles.first
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            List {
                // General settings section
                Section("General") {
                    Toggle("Natural scrolling", isOn: Binding(
                        get: { settingsRepo.naturalScroll },
                        set: { settingsRepo.naturalScroll = $0 }
                    ))
                }

                // Profile picker section
                Section("Profiles") {
                    ForEach(profiles) { profile in
                        profileRow(profile)
                    }
                    .onDelete(perform: deleteProfiles)

                    Button(action: addProfile) {
                        Label("New Profile", systemImage: "plus.circle")
                    }
                }

                // Per-slot editor section
                if let active = activeProfile {
                    Section("Keys — \(active.name)") {
                        ForEach(Array(active.keys.enumerated()), id: \.offset) { index, key in
                            NavigationLink(destination: editKeyDestination(slotIndex: index, activeProfile: active)) {
                                slotRow(index: index, key: key)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Express Keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EditButton()
            }
        }
    }

    // MARK: - Profile row

    @ViewBuilder
    private func profileRow(_ profile: ExpressKeyProfile) -> some View {
        if renamingProfileId == profile.id {
            // Inline rename field
            HStack {
                TextField("Profile name", text: $renameText, onCommit: {
                    commitRename(profileId: profile.id)
                })
                .textFieldStyle(.roundedBorder)
                Button("Done") {
                    commitRename(profileId: profile.id)
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            HStack {
                VStack(alignment: .leading) {
                    Text(profile.name)
                        .fontWeight(profile.id == activeProfileId ? .semibold : .regular)
                    if profile.id == activeProfileId {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if profile.id == activeProfileId {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectProfile(profile)
            }
            .onLongPressGesture {
                renamingProfileId = profile.id
                renameText = profile.name
            }
        }
    }

    // MARK: - Slot row

    @ViewBuilder
    private func slotRow(index: Int, key: ExpressKey) -> some View {
        HStack {
            Text("Slot \(index + 1)")
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(key.label.isEmpty ? "(unassigned)" : key.label)
                    .foregroundStyle(key.label.isEmpty ? .secondary : .primary)
                Text(key.holdMode == .modifierHold ? "Hold" : "Tap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Edit key destination

    @ViewBuilder
    private func editKeyDestination(slotIndex: Int, activeProfile: ExpressKeyProfile) -> some View {
        EditKeySheet(
            key: activeProfile.keys[slotIndex],
            slotIndex: slotIndex,
            onSave: { updatedKey in
                saveKey(updatedKey, at: slotIndex, inProfile: activeProfile.id)
            }
        )
    }

    // MARK: - Actions

    private func selectProfile(_ profile: ExpressKeyProfile) {
        activeProfileId = profile.id
        settingsRepo.activeProfileId = profile.id.uuidString
    }

    private func addProfile() {
        let newProfile = ExpressKeyProfile.makeDefault()
        profiles.append(newProfile)
        persist()
    }

    private func deleteProfiles(at offsets: IndexSet) {
        // Enforce minimum 1 profile
        guard profiles.count > 1 else { return }
        let toDelete = offsets.map { profiles[$0].id }
        profiles.remove(atOffsets: offsets)
        // If deleted profile was active, switch to first available
        if let deletedActive = toDelete.first(where: { $0 == activeProfileId }),
           let _ = deletedActive as UUID? {
            activeProfileId = profiles.first?.id
            settingsRepo.activeProfileId = activeProfileId?.uuidString ?? ""
        }
        persist()
    }

    private func commitRename(profileId: UUID) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              let idx = profiles.firstIndex(where: { $0.id == profileId }) else {
            renamingProfileId = nil
            return
        }
        profiles[idx].name = name
        renamingProfileId = nil
        persist()
    }

    private func saveKey(_ key: ExpressKey, at slotIndex: Int, inProfile profileId: UUID) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileId }),
              slotIndex < profiles[idx].keys.count else { return }
        profiles[idx].keys[slotIndex] = key
        persist()
    }

    private func persist() {
        store.saveProfiles(profiles)
    }
}
