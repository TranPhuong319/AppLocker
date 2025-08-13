import Foundation

extension String {
    /// Lấy chuỗi đã dịch từ Localizable.strings
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
    
    /// Lấy chuỗi đã dịch và format với tham số
    /// Ví dụ: "Waiting_for_%d_task_...".localized(with: 3)
    func localized(with arguments: CVarArg...) -> String {
        String(format: self.localized, arguments: arguments)
    }
}
