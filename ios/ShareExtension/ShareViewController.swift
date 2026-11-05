import UIKit
import SwiftUI

final class ShareViewController: UIViewController {
    private let model = MobileSession()
    private var loading: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let content = UIHostingController(rootView: ShareConfirmationView(model: model) { [weak self] in
            self?.loading?.cancel()
            self?.model.cancel()
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        })
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content.view)
        NSLayoutConstraint.activate([
            content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        content.didMove(toParent: self)
        model.importing = true
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        loading = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await ShareImageLoader.load(from: items)
                try Task.checkCancellation()
                await model.importGarment(image)
            } catch {
                guard !Task.isCancelled else { return }
                model.importing = false
                model.error = (error as? ToolError)?.localizedDescription ?? "无法读取截图，请重新分享一张图片。"
            }
        }
    }
}

@MainActor
private struct ShareConfirmationView: View {
    @ObservedObject var model: MobileSession
    let finish: () -> Void
    var body: some View {
        NavigationStack {
            MobileTryonPage(model: model)
                .navigationTitle("确认换装").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(model.result == nil ? "取消" : "完成", action: finish) }
                }
        }.tint(.mint)
    }
}
