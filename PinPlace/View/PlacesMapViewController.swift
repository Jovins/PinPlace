//
//  PlacesMapViewController.swift
//  PinPlace
//
//  Created by Artem on 6/7/16.
//  Copyright © 2016 Artem. All rights reserved.
//

import UIKit
import MapKit
import PKHUD
import RxSwift
import RxCocoa
import RxMKMapView

class PlacesMapViewController: UIViewController {

    fileprivate enum AppMode {
        case `default`, routing
    }

    // MARK: - Properties

    @IBOutlet fileprivate weak var routeBarButtonItem: UIBarButtonItem!
    @IBOutlet fileprivate weak var longPressGestureRecognizer: UILongPressGestureRecognizer!
    @IBOutlet fileprivate weak var mapView: MKMapView!

    fileprivate let disposeBag = DisposeBag()
    let viewModel = PlacesMapViewModel()
    fileprivate var appMode: AppMode = .default

    deinit {
        removeNotifications()
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        subscribeOnNotifications()
        setupMapForUpdatingUserLocation()

        longPressGestureRecognizer.rx.event.bind { [unowned self] longPressGesture in
            if longPressGesture.state != .ended {
                return
            }
            let touchPoint = longPressGesture.location(in: self.mapView)
            let touchLocationCoordinate2D = self.mapView.convert(touchPoint, toCoordinateFrom: self.mapView)
            self.viewModel.appendPlaceWithCoordinate(touchLocationCoordinate2D)
            self.mapView.addAnnotation(self.viewModel.places.value.last!)

            }.disposed(by: disposeBag)

        mapView.rx.annotationViewCalloutAccessoryControlTapped.bind { [unowned self] view, _ in
            if view.annotation is Place {
                self.mapView.deselectAnnotation(view.annotation, animated: false)
                self.performSegue(withIdentifier: SegueIdentifier.showPlaceDetails.rawValue, sender: view.annotation)
            }
            }.disposed(by: disposeBag)

        mapView.rx.didUpdateUserLocation.bind { [unowned self] _ in
            guard let userLocation = self.mapView.userLocation.location else { return }
            let coordinateSpan = MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            let locationCoordinate = CLLocationCoordinate2D(latitude: userLocation.coordinate.latitude,
                                                            longitude: userLocation.coordinate.longitude)
            self.viewModel.userLocationCoordinate2D = locationCoordinate
            let region = MKCoordinateRegion(center: locationCoordinate, span: coordinateSpan)
            self.mapView.setRegion(region, animated: true)
            }.disposed(by: disposeBag)

        routeBarButtonItem.rx.tap.bind { [unowned self] in
            switch self.appMode {
            case .default:
                self.performSegue(withIdentifier: SegueIdentifier.showPopover.rawValue, sender: self)
            case .routing:
                self.switchAppToNormalMode()
            }
            }.disposed(by: disposeBag)

        viewModel.places.asDriver().drive(onNext: { [weak self] placesAnnotations in
            self?.mapView.addAnnotations(placesAnnotations)
        }).disposed(by: disposeBag)

        viewModel.currentRouteMKDirectionsResponse.asDriver().drive(onNext: { [weak self] mkDirectionsResponse in
            guard let weakSelf = self else { return }
            if let mkDirectionsResponse = mkDirectionsResponse {
                var totalRect = MKMapRect.null
                for route in mkDirectionsResponse.routes {
                    weakSelf.mapView.addOverlay(route.polyline, level: .aboveRoads)
                    let polygon = MKPolygon(points: route.polyline.points(), count: route.polyline.pointCount)
                    let routeRect = polygon.boundingMapRect
                    totalRect = totalRect.union(routeRect)
                }
                weakSelf.mapView.setVisibleMapRect(totalRect, edgePadding: UIEdgeInsets(top: 30,
                                                                                        left: 30,
                                                                                        bottom: 30,
                                                                                        right: 30),
                                                   animated: true)
            } else {
                weakSelf.mapView.removeAnnotations(weakSelf.mapView.annotations)
                weakSelf.mapView.removeOverlays(weakSelf.mapView.overlays)
            }
        }).disposed(by: disposeBag)

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if appMode == .default {
            viewModel.fetchPlaces()
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == SegueIdentifier.showPopover.rawValue {
            guard let destVC = segue.destination as? PlacesPopoverTableViewController,
                  let destPopoverVC = destVC.popoverPresentationController else {
                return
            }
            destPopoverVC.delegate = self
        } else if segue.identifier == SegueIdentifier.showPlaceDetails.rawValue {
            guard let place = sender as? Place,
                  let placeDetailsViewController = segue.destination as? PlaceDetailsViewController
                    else { return }
            placeDetailsViewController.viewModel.place = place
        }
    }

    // MARK: - NSNotificationCenter Handlers

    @objc private func buildRoute() {
        appMode = .routing
        routeBarButtonItem.title = "Clear Route"
        HUD.show(.progress)
        viewModel.buildRoute { [weak self] errorMessage in
            HUD.flash(.success, delay: 1.0)
            guard let weakSelf = self else { return }
            if let errorMessage = errorMessage {
                let alertController = UIAlertController(title: "Error", message: errorMessage, preferredStyle: .alert)
                let cancelAction = UIAlertAction(title: "OK", style: .cancel) { (_) in
                }
                alertController.addAction(cancelAction)
                DispatchQueue.main.async {
                    weakSelf.present(alertController, animated: true, completion: nil)
                }
            } else {
                if let targetAnnotation = weakSelf.viewModel.selectedTargetPlace {
                    weakSelf.mapView.addAnnotation(targetAnnotation)
                }
            }
        }
    }

    @objc private func placeDeletedNotification(_ notification: Notification) {
        if let notificationObject = notification.object as? Place,
           let selectedTargetPlace =  self.viewModel.selectedTargetPlace {
            if notificationObject == selectedTargetPlace && appMode == .routing {
                self.switchAppToNormalMode()
            }
        }
    }

    @objc private func centerPlaceNotification(_ notification: Notification) {
        if let notificationObject = notification.object as? Place {
            if self.appMode != .default {
                switchAppToNormalMode()
            }
            guard let location = notificationObject.location as? CLLocation else {return}
            let centerCoordinate = CLLocationCoordinate2D(latitude: location.coordinate.latitude,
                                                          longitude: location.coordinate.longitude)
            var region = self.mapView.region
            region.center = centerCoordinate
            self.mapView.setRegion(region, animated: true)
        }
    }

    // MARK: - Private

    fileprivate func setupMapForUpdatingUserLocation() {
        self.viewModel.setupLocationManagerWithDelegate(self)
        mapView.showsUserLocation = true
        mapView.showsPointsOfInterest = true
    }

    fileprivate func switchAppToNormalMode() {
        self.appMode = .default
        self.routeBarButtonItem.title = "Route"
        self.viewModel.clearRoute()
        viewModel.fetchPlaces()
    }

    fileprivate func subscribeOnNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(centerPlaceNotification),
                                               name: .centerPlaceOnMap,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(buildRoute),
                                               name: .buildRoute,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(placeDeletedNotification),
                                               name: .placeDeleted,
                                               object: nil)
    }

    fileprivate func removeNotifications() {
        NotificationCenter.default.removeObserver(self,
                                                  name: .centerPlaceOnMap,
                                                  object: nil)

        NotificationCenter.default.removeObserver(self,
                                                  name: .buildRoute,
                                                  object: nil)

        NotificationCenter.default.removeObserver(self,
                                                  name: .placeDeleted,
                                                  object: nil)
    }
}

// MARK: - CLLocationManagerDelegate

extension PlacesMapViewController: CLLocationManagerDelegate {

}

// MARK: - MKMapViewDelegate

extension PlacesMapViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return mapView.view(for: annotation)
        }
        let placeAnnotationView = MKPinAnnotationView(annotation: annotation,
                                                      reuseIdentifier: "PlaceAnnotationViewIdentifier")
        placeAnnotationView.canShowCallout = true
        placeAnnotationView.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        return placeAnnotationView
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let polylineRenderer = MKPolylineRenderer(overlay: overlay)
        polylineRenderer.strokeColor = UIColor(red:0.29, green:0.53, blue:0.91, alpha:1.0)
        polylineRenderer.lineWidth = 5.0
        return polylineRenderer
    }
}

// MARK: - UIPopoverPresentationControllerDelegate

extension PlacesMapViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController,
                                   traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
}
