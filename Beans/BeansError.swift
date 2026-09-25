import Foundation

/// 全局通用错误（原 NetEaseError，酷狗等模块沿用）。
enum NetEaseError: LocalizedError {
    case network
    case httpStatus(Int, String)
    case decoding(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .network: return "网络请求失败，请稍后重试"
        case .httpStatus(let code, let snippet):
            return snippet.isEmpty ? "服务端响应异常（\(code)）" : "服务端响应异常（\(code)）\(snippet)"
        case .decoding(let snippet):
            return snippet.isEmpty ? "数据解析失败" : "数据解析失败（\(snippet)）"
        case .unknown(let message): return message
        }
    }
}
