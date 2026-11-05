import Foundation
import ScreenCaptureKit

enum CaptureFailure: LocalizedError {
    case permissionDenied
    case unavailable(Int)

    static func classify(_ error: Error) -> Error {
        if error is ToolError || error is CaptureFailure { return error }
        let native = error as NSError
        // Only the actual capture API's denial is treated as a permission failure.
        if native.domain == SCStreamErrorDomain && native.code == SCStreamError.Code.userDeclined.rawValue {
            return CaptureFailure.permissionDenied
        }
        return CaptureFailure.unavailable(native.code)
    }

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "macOS 尚未允许当前运行的应用截图。如果设置里的开关已经开启，可能对应旧版本或另一份应用；请重新授权当前应用后重试。"
        case .unavailable(let code):
            return "系统截图服务暂不可用（错误代码 \(code)）。请重试；若仍失败，请重新打开工具。"
        }
    }
}
