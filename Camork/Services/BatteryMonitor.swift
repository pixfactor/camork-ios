import UIKit
import Combine

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published var batteryLevel: Float = 1.0
    @Published var isLowBattery: Bool = false
    
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBatteryState()
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateBatteryState()
            }
        }
    }
    
    private func updateBatteryState() {
        batteryLevel = UIDevice.current.batteryLevel
        isLowBattery = batteryLevel < 0.1 && batteryLevel >= 0
    }
    
    func stopMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = false
    }
}
