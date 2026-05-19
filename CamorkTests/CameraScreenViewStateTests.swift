import Testing
@testable import Camork

@Suite("CameraScreenViewState")
struct CameraScreenViewStateTests {

    // MARK: - Happy path (camera + location 모두 granted)

    @Test("granted+granted + pending=false + inFlight=false → cameraActive(.idle)")
    func cameraActiveIdle() {
        let v = CameraScreenViewState.compute(
            camera: .granted, location: .granted,
            isPending: false, isInFlight: false
        )
        #expect(v == .cameraActive(chip: .idle))
    }

    @Test("isPending=true + inFlight=false → cameraActive(.pending)")
    func chipPending() {
        let v = CameraScreenViewState.compute(
            camera: .granted, location: .granted,
            isPending: true, isInFlight: false
        )
        #expect(v == .cameraActive(chip: .pending))
    }

    @Test("isInFlight=true → cameraActive(.disabled) — isPending false에서도 disabled")
    func chipDisabledWhileInFlight_pendingFalse() {
        let v = CameraScreenViewState.compute(
            camera: .granted, location: .granted,
            isPending: false, isInFlight: true
        )
        #expect(v == .cameraActive(chip: .disabled))
    }

    @Test("isInFlight=true → cameraActive(.disabled) — isPending true에서도 disabled (in-flight 우선)")
    func chipDisabledWhileInFlight_pendingTrue() {
        let v = CameraScreenViewState.compute(
            camera: .granted, location: .granted,
            isPending: true, isInFlight: true
        )
        #expect(v == .cameraActive(chip: .disabled))
    }

    // MARK: - Camera permission issues (location 상태 무관, camera 우선)

    @Test("camera=.denied → permissionDenied(.camera), location 상태 무관")
    func cameraDeniedAcrossAllLocations() {
        for loc: PermissionState in [.granted, .denied, .notDetermined, .restricted] {
            let v = CameraScreenViewState.compute(
                camera: .denied, location: loc,
                isPending: false, isInFlight: false
            )
            #expect(v == .permissionDenied(target: .camera), "loc=\(loc)")
        }
    }

    @Test("camera=.restricted → permissionDenied(.camera)")
    func cameraRestricted() {
        let v = CameraScreenViewState.compute(
            camera: .restricted, location: .granted,
            isPending: false, isInFlight: false
        )
        #expect(v == .permissionDenied(target: .camera))
    }

    @Test("camera=.notDetermined → requestPrompt, location 상태 무관")
    func cameraNotDeterminedAcrossAllLocations() {
        for loc: PermissionState in [.granted, .denied, .notDetermined, .restricted] {
            let v = CameraScreenViewState.compute(
                camera: .notDetermined, location: loc,
                isPending: false, isInFlight: false
            )
            #expect(v == .requestPrompt, "loc=\(loc)")
        }
    }

    @Test("camera=.denied + isInFlight=true → permissionDenied(.camera) — chip 무시 (permission이 더 우선)")
    func cameraDeniedIgnoresChip() {
        let v = CameraScreenViewState.compute(
            camera: .denied, location: .granted,
            isPending: true, isInFlight: true
        )
        #expect(v == .permissionDenied(target: .camera))
    }

    // MARK: - Location permission (camera granted 전제)

    @Test("camera=.granted + location=.denied → permissionDenied(.location)")
    func locationDeniedAfterCameraGranted() {
        let v = CameraScreenViewState.compute(
            camera: .granted, location: .denied,
            isPending: false, isInFlight: false
        )
        #expect(v == .permissionDenied(target: .location))
    }

    @Test("camera=.granted + location=.restricted → permissionDenied(.location)")
    func locationRestrictedAfterCameraGranted() {
        let v = CameraScreenViewState.compute(
            camera: .granted, location: .restricted,
            isPending: false, isInFlight: false
        )
        #expect(v == .permissionDenied(target: .location))
    }

    @Test("camera=.granted + location=.notDetermined → requestPrompt")
    func locationNotDeterminedAfterCameraGranted() {
        let v = CameraScreenViewState.compute(
            camera: .granted, location: .notDetermined,
            isPending: false, isInFlight: false
        )
        #expect(v == .requestPrompt)
    }

    // MARK: - Precedence (deterministic ordering)

    @Test("Precedence: camera=.denied + location=.notDetermined → permissionDenied(.camera) (camera 우선)")
    func precedence_cameraDeniedBeatsLocationNotDetermined() {
        let v = CameraScreenViewState.compute(
            camera: .denied, location: .notDetermined,
            isPending: false, isInFlight: false
        )
        #expect(v == .permissionDenied(target: .camera))
    }

    @Test("Precedence: camera=.notDetermined + location=.denied → requestPrompt (camera 분기 우선)")
    func precedence_cameraNotDeterminedBeatsLocationDenied() {
        let v = CameraScreenViewState.compute(
            camera: .notDetermined, location: .denied,
            isPending: false, isInFlight: false
        )
        #expect(v == .requestPrompt)
    }
}
