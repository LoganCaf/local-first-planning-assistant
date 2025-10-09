import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
final class LocationServices: NSObject, ObservableObject {
    static let shared = LocationServices()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var lastError: Error?

    private let manager: CLLocationManager

    override init() {
        manager = CLLocationManager()
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }
}

extension LocationServices: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
                startUpdating()
            } else {
                currentLocation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location
            lastError = nil
            stopUpdating()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error
        }
    }
}

struct TravelTimeResult {
    var drivingMinutes: Int?
    var walkingMinutes: Int?
}

enum TravelTimeError: LocalizedError {
    case missingOrigin
    case calculationFailed

    var errorDescription: String? {
        switch self {
        case .missingOrigin:
            return "현재 위치를 확인할 수 없어 이동 시간을 계산하지 못했어요."
        case .calculationFailed:
            return "경로를 계산하지 못했어요. 장소를 다시 선택하거나 잠시 후 시도해주세요."
        }
    }
}

enum TravelMode {
    case driving
    case walking

    var transportType: MKDirectionsTransportType {
        switch self {
        case .driving:
            return .automobile
        case .walking:
            return .walking
        }
    }
}

struct TravelTimeCalculator {
    static func estimateTravel(origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) async throws -> TravelEstimates {
        async let driving = minutes(for: origin, destination: destination, mode: .driving)
        async let walking = minutes(for: origin, destination: destination, mode: .walking)

        let drivingMinutes = try await driving
        let walkingMinutes = try await walking

        if drivingMinutes == nil && walkingMinutes == nil {
            throw TravelTimeError.calculationFailed
        }

        return TravelEstimates(
            drivingMinutes: drivingMinutes,
            walkingMinutes: walkingMinutes,
            lastUpdated: Date()
        )
    }

    private static func minutes(for origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D, mode: TravelMode) async throws -> Int? {
        let request = MKDirections.Request()
        request.source = makeMapItem(for: origin)
        request.destination = makeMapItem(for: destination)
        request.transportType = mode.transportType

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let expected = response.routes.first?.expectedTravelTime else {
                return nil
            }
            let minutes = Int((expected / 60.0).rounded())
            return max(minutes, 0)
        } catch {
            return nil
        }
    }
}

private func makeMapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
    if #available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, visionOS 1.0, *) {
        return MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
    } else {
        return MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    }
}
