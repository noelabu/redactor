import Observation
import RedactorCore
import SwiftUI

@MainActor
@Observable
final class PreviewModel {
    let image: CGImage
    var boxes: [RedactionBox]
    /// True while OCR and detection are still running; editing and Save wait for it.
    var isLoading: Bool
    /// What detection is doing right now, shown while loading.
    var stage = "Reading text…"
    /// How the boxes were found, e.g. "AI check on".
    var status: String?
    /// Rubber-band rect while dragging, in image pixels.
    var draft: CGRect?

    init(image: CGImage, boxes: [RedactionBox], isLoading: Bool = false) {
        self.image = image
        self.boxes = boxes
        self.isLoading = isLoading
    }

    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    var activeCount: Int { boxes.filter(\.enabled).count }

    func toggle(_ id: UUID) {
        guard let i = boxes.firstIndex(where: { $0.id == id }) else { return }
        boxes[i].enabled.toggle()
    }

    func addBox(_ rect: CGRect) {
        let clamped = rect.standardized.intersection(CGRect(origin: .zero, size: imageSize)).integral
        guard clamped.width >= 2, clamped.height >= 2 else { return }
        boxes.append(RedactionBox(rect: clamped, kind: .manual))
    }
}

struct PreviewView: View {
    @Bindable var model: PreviewModel
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let scale = min(geo.size.width / model.imageSize.width, geo.size.height / model.imageSize.height)
                canvas(scale: scale)
                    .frame(width: model.imageSize.width * scale, height: model.imageSize.height * scale)
                    .allowsHitTesting(!model.isLoading)
                    .overlay {
                        if model.isLoading {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(model.stage)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .underPageBackgroundColor))

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Click a box to toggle · Drag to add a box")
                    Text(model.isLoading ? "\(model.boxes.count) found so far" : ([
                        "\(model.activeCount) of \(model.boxes.count) boxes active", model.status,
                    ].compactMap { $0 }.joined(separator: " · ")))
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                Spacer()
                Button("Close", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isLoading)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
        }
        .frame(minWidth: 420, minHeight: 200)
    }

    private func canvas(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: model.image, scale: 1)
                .resizable()
                .interpolation(.high)

            ForEach(model.boxes) { box in
                boxView(box)
                    .frame(width: box.rect.width * scale, height: box.rect.height * scale)
                    .offset(x: box.rect.minX * scale, y: box.rect.minY * scale)
                    .onTapGesture { model.toggle(box.id) }
            }

            if let draft = model.draft?.standardized {
                Rectangle()
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .frame(width: draft.width * scale, height: draft.height * scale)
                    .offset(x: draft.minX * scale, y: draft.minY * scale)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    model.draft = CGRect(
                        x: value.startLocation.x / scale, y: value.startLocation.y / scale,
                        width: value.translation.width / scale, height: value.translation.height / scale
                    )
                }
                .onEnded { _ in
                    if let draft = model.draft { model.addBox(draft) }
                    model.draft = nil
                }
        )
    }

    @ViewBuilder
    private func boxView(_ box: RedactionBox) -> some View {
        if box.enabled {
            Rectangle().fill(Color.black)
        } else {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .overlay(Rectangle().stroke(Color.red, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
        }
    }
}
