import Foundation
import UIKit
import LocalAuthentication

final class OwnerGuard {
    private let bindingKey = "4move.owner.binding.v1"
    private let modeKey = "4move.owner.mode.v1"
    private let defaults = UserDefaults.standard

    var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    private var boundId: String {
        defaults.string(forKey: bindingKey) ?? ""
    }

    private var isBoundDevice: Bool {
        !boundId.isEmpty && boundId == deviceId
    }

    var isOwner: Bool {
        get { defaults.bool(forKey: modeKey) && isBoundDevice }
        set { defaults.set(newValue && isBoundDevice, forKey: modeKey) }
    }

    init() {
        if boundId.isEmpty { bind() }
    }

    func bind() {
        defaults.set(deviceId, forKey: bindingKey)
        defaults.set(true, forKey: modeKey)
    }

    func shortId() -> String {
        let compact = deviceId.replacingOccurrences(of: "-", with: "")
        return String(compact.suffix(8)).uppercased()
    }

    func statusText() -> String {
        let state = isOwner ? "ДОВЕРЕННЫЙ ВЛАДЕЛЕЦ" : "ОГРАНИЧЕННЫЙ РЕЖИМ"
        return """
        ПРИВЯЗКА К ВЛАДЕЛЬЦУ

          Статус: \(state)
          Устройство: \(shortId())
          Привязка найдена: \(isBoundDevice ? "да" : "нет")

        Команды принимаются только после разблокировки владельцем устройства.
        """
    }

    func unlock(reason: String = "Подтвердите, что вы владелец 4MOVE", completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = "Отмена"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
    }
}
