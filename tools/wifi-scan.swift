#!/usr/bin/env swift
// CoreWLAN scan — one JSON object per line on stdout
import Foundation
import CoreWLAN

struct NetworkOut: Encodable {
    let ssid: String
    let bssid: String
    let channel: Int
    let band: String
    let rssi: Int
    let security: String
}

func bandLabel(for channel: CWChannel?) -> String {
    guard let ch = channel else { return "unknown" }
    switch ch.channelBand {
    case .band2GHz: return "2g"
    case .band5GHz: return "5g"
    case .band6GHz: return "6g"
    case .bandUnknown: return "unknown"
    @unknown default: return "unknown"
    }
}

func securityLabel(_ net: CWNetwork) -> String {
    if net.supportsSecurity(.wpa3Personal) || net.supportsSecurity(.wpa3Enterprise) {
        return "WPA3"
    }
    if net.supportsSecurity(.wpa2Personal) || net.supportsSecurity(.wpa2Enterprise) {
        return "WPA2"
    }
    if net.supportsSecurity(.wpaPersonal) || net.supportsSecurity(.wpaEnterprise) {
        return "WPA"
    }
    if net.supportsSecurity(.dynamicWEP) {
        return "WEP"
    }
    if net.supportsSecurity(.none) {
        return "OPEN"
    }
    return "UNKNOWN"
}

let iface = CWWiFiClient.shared().interface()
guard let wifi = iface else {
    fputs("{\"error\":\"No Wi-Fi interface available\"}\n", stderr)
    exit(1)
}

guard let networks = try? wifi.scanForNetworks(withName: nil) else {
    fputs("{\"error\":\"Scan failed — grant Location/Wi-Fi access or retry\"}\n", stderr)
    exit(1)
}

let encoder = JSONEncoder()
encoder.outputFormatting = []

for net in networks.sorted(by: { $0.rssiValue > $1.rssiValue }) {
    let ssid = net.ssid ?? "<hidden>"
    let bssid = net.bssid ?? ""
    let ch = net.wlanChannel?.channelNumber ?? 0
    let out = NetworkOut(
        ssid: ssid,
        bssid: bssid,
        channel: ch,
        band: bandLabel(for: net.wlanChannel),
        rssi: net.rssiValue,
        security: securityLabel(net)
    )
    if let data = try? encoder.encode(out),
       let line = String(data: data, encoding: .utf8) {
        print(line)
    }
}
