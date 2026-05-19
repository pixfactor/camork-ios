import Testing
import AVFoundation
import CoreLocation
@testable import Camork

@Suite("PermissionsService")
struct PermissionsServiceTests {

    // MARK: - Camera (AVAuthorizationStatus → PermissionState)

    @Test("AVAuthorizationStatus.authorized → .granted")
    func cameraAuthorized() {
        #expect(PermissionsService.map(camera: .authorized) == .granted)
    }

    @Test("AVAuthorizationStatus.notDetermined → .notDetermined")
    func cameraNotDetermined() {
        #expect(PermissionsService.map(camera: .notDetermined) == .notDetermined)
    }

    @Test("AVAuthorizationStatus.denied → .denied")
    func cameraDenied() {
        #expect(PermissionsService.map(camera: .denied) == .denied)
    }

    @Test("AVAuthorizationStatus.restricted → .restricted")
    func cameraRestricted() {
        #expect(PermissionsService.map(camera: .restricted) == .restricted)
    }

    // MARK: - Location (CLAuthorizationStatus → PermissionState)

    @Test("CLAuthorizationStatus.authorizedAlways → .granted")
    func locationAuthorizedAlways() {
        #expect(PermissionsService.map(location: .authorizedAlways) == .granted)
    }

    @Test("CLAuthorizationStatus.authorizedWhenInUse → .granted")
    func locationAuthorizedWhenInUse() {
        #expect(PermissionsService.map(location: .authorizedWhenInUse) == .granted)
    }

    @Test("CLAuthorizationStatus.notDetermined → .notDetermined")
    func locationNotDetermined() {
        #expect(PermissionsService.map(location: .notDetermined) == .notDetermined)
    }

    @Test("CLAuthorizationStatus.denied → .denied")
    func locationDenied() {
        #expect(PermissionsService.map(location: .denied) == .denied)
    }

    @Test("CLAuthorizationStatus.restricted → .restricted")
    func locationRestricted() {
        #expect(PermissionsService.map(location: .restricted) == .restricted)
    }
}
