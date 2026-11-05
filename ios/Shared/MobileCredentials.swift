import Foundation
import Security

struct MobilePreferences: Codable {
    var usePersonalModel = false
    var serverModel = "doubao"
    var provider = "doubao"
    var baseURL = "https://ark.cn-beijing.volces.com/api/v3"
    var apiKey = ""
    var model = ""
    var token = ""

    func personalModel() throws -> PersonalModel? {
        guard usePersonalModel else { return nil }
        let configuration = PersonalModel(provider: provider, base_url: baseURL, api_key: apiKey, model: model)
        try configuration.validate()
        return configuration
    }
}

struct MobileCredentials {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.personalcloakroom.ios.model-settings",
         kSecAttrAccount as String: "personal-model",
         kSecAttrAccessGroup as String: MobileEnvironment.groupIdentifier]
    }

    func load() throws -> MobilePreferences {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &value)
        if status == errSecItemNotFound { return MobilePreferences() }
        guard status == errSecSuccess, let data = value as? Data,
              let settings = try? JSONDecoder().decode(MobilePreferences.self, from: data) else {
            throw ToolError.message("无法读取共享钥匙串，请检查 App Groups 签名配置或解锁设备后重试。")
        }
        return settings
    }

    func save(_ preferences: MobilePreferences) throws {
        _ = try preferences.personalModel()
        let bytes = try JSONEncoder().encode(preferences)
        let update: [String: Any] = [kSecValueData as String: bytes,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            update.forEach { item[$0.key] = $0.value }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ToolError.message("无法保存模型配置，请检查共享钥匙串签名权限。") }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ToolError.message("无法清除模型配置，请解锁设备后重试。")
        }
    }
}
