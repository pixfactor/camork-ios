import Testing
@testable import Camork

@Suite("CameraScreenViewState")
struct CameraScreenViewStateTests {

    // MARK: - Happy path (camera granted, location optional)

    @Test("camera granted + location granted + pending=false + inFlight=false → cameraActive(.idle)")
    func cameraActiveIdle() {
        let v = CameraScreenViewState.compute(
            camera: .granted, location: .granted,
            isPending: false, isInFlight: false
        )
        #expect(v == .cameraActive(chip: .idle))
    }

    @Test("camera granted이면 location denied여도 cameraActive — 위치는 optional metadata")
    func locationDeniedStillCameraActive() {
        let v = CameraScreenViewState.compute(
            camera: .granted, location: .denied,
            isPending: false, isInFlight: false
        )
        #expect(v == .cameraActive(chip: .idle))
    }

    @Test("camera granted이면 location restricted여도 cameraActive")
    func locationRestrictedStillCameraActive() {
        let v = CameraScreenViewState.compute(
            camera: .granted, location: .restricted,
            isPending: false, isInFlight: false
        )
        #expect(v == .cameraActive(chip: .idle))
    }

    @Test("camera granted이면 location notDetermined여도 cameraActive — prompt는 첫 촬영에서 처리")
    func locationNotDeterminedStillCameraActive() {
        let v = CameraScreenViewState.compute(
            camera: .granted, location: .notDetermined,
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
