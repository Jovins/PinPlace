//
//  PlacesPopoverTableViewController.swift
//  PinPlace
//
//  Created by Artem on 6/8/16.
//  Copyright © 2016 Artem. All rights reserved.
//

import UIKit
import RxSwift

class PlacesPopoverTableViewController: UIViewController {

    // MARK: - Properties

    @IBOutlet fileprivate weak var tableView: UITableView!
    let viewModel = PlacesViewModel()
    fileprivate let disposeBag = DisposeBag()

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(PlaceTableViewCell.nib,
                           forCellReuseIdentifier: PlaceTableViewCell.reuseIdentifier)

        viewModel.fetchPlaces()

        viewModel.places
                .asDriver()
                .drive(tableView.rx.items(cellIdentifier: PlaceTableViewCell.reuseIdentifier,
                                          cellType: PlaceTableViewCell.self)) { _, place, cell in
                    cell.placeTitleLabel.text = place.title
            }.disposed(by: disposeBag)

        tableView.rx.itemSelected.bind { [unowned self] indexPath in
            if let placesMapVC = self.popoverPresentationController?.delegate as? PlacesMapViewController {
                placesMapVC.viewModel.selectedTargetPlace = self.viewModel.places.value[indexPath.row]
                NotificationCenter.default.post(name: .buildRoute, object: nil)
            }
            self.dismiss(animated: true, completion: nil)
            }.disposed(by: disposeBag)
    }
}
