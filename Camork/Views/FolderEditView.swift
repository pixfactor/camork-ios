import SwiftUI
import SwiftData
import CryptoKit

struct FolderEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var folder: Folder?

    @State private var name: String = ""
    @State private var selectedColor: Color = Color(hex: "#007AFF")
    @State private var isPasswordEnabled: Bool = false
    @State private var passwordInput: String = ""
    @State private var passwordConfirm: String = ""

    private let presetColors: [String] = [
        "#007AFF", "#34C759", "#FF3B30", "#FF9500",
        "#FFCC00", "#5856D6", "#FF2D55", "#5AC8FA"
    ]

    private var isEditMode: Bool { folder != nil }

    init(folder: Folder? = nil) {
        self.folder = folder
        if let folder {
            _name = State(initialValue: folder.name)
            _selectedColor = State(initialValue: Color(hex: folder.colorHex))
            _isPasswordEnabled = State(initialValue: folder.isLocked)
            _passwordInput = State(initialValue: "")
            _passwordConfirm = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("폴더 이름") {
                    TextField("업무, 현장, 보고서...", text: $name)
                }

                Section("색상") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(presetColors, id: \.self) { hex in
                            presetColorButton(hex: hex)
                        }
                    }
                    .padding(.vertical, 4)

                    ColorPicker("커스텀 색상", selection: $selectedColor, supportsOpacity: false)
                }

                Section("보안") {
                    Toggle("비밀번호 잠금", isOn: $isPasswordEnabled)

                    if isPasswordEnabled {
                        SecureField("4자리 숫자", text: $passwordInput)
                            .keyboardType(.numberPad)
                            .onChange(of: passwordInput) { _, newValue in
                                if newValue.count > 4 {
                                    passwordInput = String(newValue.prefix(4))
                                }
                                passwordInput = newValue.filter { $0.isNumber }
                            }
                        SecureField("비밀번호 확인", text: $passwordConfirm)
                            .keyboardType(.numberPad)
                            .onChange(of: passwordConfirm) { _, newValue in
                                if newValue.count > 4 {
                                    passwordConfirm = String(newValue.prefix(4))
                                }
                                passwordConfirm = newValue.filter { $0.isNumber }
                            }
                    }
                }

                Section {
                    colorPreview
                }
            }
            .navigationTitle(isEditMode ? "폴더 편집" : "새 폴더")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func presetColorButton(hex: String) -> some View {
        let color = Color(hex: hex)
        let isSelected = color.toHex().uppercased() == selectedColor.toHex().uppercased()
        return Button {
            selectedColor = color
        } label: {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(isSelected ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    private var colorPreview: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundStyle(selectedColor)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "폴더 이름" : name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(name.isEmpty ? .secondary : .primary)
                Text("미리보기")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let hex = selectedColor.toHex()

        // Handle password
        var lockFlag = false
        var hash: String? = nil

        if isPasswordEnabled && passwordInput.count == 4 && passwordInput == passwordConfirm {
            lockFlag = true
            hash = SHA256.hash(data: Data(passwordInput.utf8))
                .compactMap { String(format: "%02x", $0) }
                .joined()
        } else if !isPasswordEnabled {
            lockFlag = false
            hash = nil
        }

        if let folder {
            folder.name = trimmed
            folder.colorHex = hex
            folder.isLocked = lockFlag
            folder.passwordHash = hash
        } else {
            let maxOrder = try? modelContext.fetch(FetchDescriptor<Folder>()).map(\.sortOrder).max()
            let newFolder = Folder(
                name: trimmed,
                colorHex: hex,
                sortOrder: (maxOrder ?? -1) + 1,
                isLocked: lockFlag,
                passwordHash: hash
            )
            modelContext.insert(newFolder)
        }
        dismiss()
    }
}
