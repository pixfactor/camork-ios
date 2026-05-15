import SwiftUI

struct MemoTemplateSheet: View {
    @Bindable var item: MediaItem
    var onDismiss: (Bool) -> Void

    @State private var selectedTemplate: MemoTemplate?
    @State private var customMemo: String = ""
    @State private var skipNextTime: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("이 사진의 용도는?")
                    .font(.headline)
                    .padding(.top, 24)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(MemoTemplate.allCases) { template in
                        Button {
                            selectedTemplate = template
                            customMemo = template.defaultMemo
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: template.icon)
                                    .font(.title)
                                Text(template.rawValue)
                                    .font(.subheadline.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(selectedTemplate == template ? Color.accentColor : Color(.systemGray6))
                            )
                            .foregroundStyle(selectedTemplate == template ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                if selectedTemplate != nil {
                    TextField("추가 메모...", text: $customMemo, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .padding(.horizontal)
                }

                Toggle("다음부터 건너뛰기", isOn: $skipNextTime)
                    .font(.subheadline)
                    .padding(.horizontal)

                Spacer()

                Button {
                    saveMemo()
                } label: {
                    Text(selectedTemplate == nil ? "건너뛰기" : "저장")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedTemplate == nil ? Color(.systemGray5) : Color.accentColor)
                        )
                        .foregroundStyle(selectedTemplate == nil ? .secondary : Color.white)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("빠른 메모")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("건너뛰기") {
                        onDismiss(skipNextTime)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func saveMemo() {
        item.templateTag = selectedTemplate?.rawValue
        item.memo = customMemo
        onDismiss(skipNextTime)
    }
}
