import Foundation

/// Abstraksi core VPN agar bisa diganti (sing-box default, mihomo cadangan).
public protocol VPNCore {
    var name: String { get }
    func configJSON(node: ProxyNode, split: SplitTunnelConfig, clashPort: Int, mixedPort: Int, tunEnabled: Bool) -> String
    func validate(configPath: String, coreBinary: String) -> Bool
}
