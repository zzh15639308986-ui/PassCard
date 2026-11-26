import SwiftUI

@MainActor
struct PassRowView: View {
    let pass: Pass
    @EnvironmentObject private var store: PassStore

    private var presentation: PassPresentation { pass.presentation }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(pass.type.tint.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: pass.type.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(pass.type.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(presentation.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if pass.isPinned {
                        Text("锁屏")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(pass.type.tint.opacity(0.18), in: Capsule())
                            .foregroundStyle(pass.type.tint)
                    }
                }

                Text(presentation.primary)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(pass.isCompleted ? Color.secondary : Color.primary)

                if !presentation.secondary.isEmpty {
                    Text(presentation.secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if pass.isCompleted, let completedAt = pass.completedAt {
                    Text("\(pass.type.completionVerb) · \(PassFormatter.shortDate(completedAt))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .opacity(pass.isCompleted ? 0.6 : 1)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                remove()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            if pass.isCompleted {
                Button {
                    reopen()
                } label: {
                    Label("恢复", systemImage: "arrow.uturn.backward")
                }
                .tint(.gray)
            } else {
                Button {
                    complete()
                } label: {
                    Label(pass.type.completionVerb, systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
            }
        }
        .contextMenu {
            if pass.isPinned {
                Button(role: .destructive) { unpin() } label: {
                    Label("从锁屏移除", systemImage: "lock.open")
                }
            } else if !pass.isCompleted {
                Button { pin() } label: {
                    Label("固定到锁屏", systemImage: "lock")
                }
            }
            Button(role: .destructive) { remove() } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func pin() {
        do {
            try LiveActivityController.start(for: pass)
            store.setPinned(true, for: pass)
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func unpin() {
        LiveActivityController.end(for: pass.id)
        store.setPinned(false, for: pass)
    }

    private func complete() {
        LiveActivityController.end(for: pass.id)
        store.markCompleted(pass)
    }

    private func reopen() {
        store.reopen(pass)
    }

    private func remove() {
        LiveActivityController.end(for: pass.id)
        store.delete(ids: [pass.id])
    }
}
