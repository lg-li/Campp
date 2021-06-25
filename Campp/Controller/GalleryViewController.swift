//
//  GalleryViewController.swift
//  Campp
//
//  Created by Lingen Li on 2020/4/2.
//  Copyright © 2020 Apple. All rights reserved.
//

import Foundation
import ElongationPreview
import UIKit

final class GalleryViewController: ElongationViewController {

    var datasource: [GalleryItem] = GalleryItem.testData

    // MARK: Lifecycle 🌎
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func openDetailView(for indexPath: IndexPath) {
        let id = String(describing: GalleryDetailViewController.self)
        guard let detailViewController = UIStoryboard(name: "Gallery", bundle: nil).instantiateViewController(withIdentifier: id) as? GalleryDetailViewController else { return }
        let galleryItem = datasource[indexPath.row]
        detailViewController.title = galleryItem.title
        expand(viewController: detailViewController)
    }
}

// MARK: - Setup ⛏
private extension GalleryViewController {

    func setup() {
        tableView.backgroundColor = UIColor.black
        tableView.register(UINib(nibName: "GalleryCell", bundle: nil), forCellReuseIdentifier: "GalleryCell") // GalleryCell.self)
    }
}

// MARK: - TableView 📚
extension GalleryViewController {

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        return datasource.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt _: IndexPath) -> UITableViewCell {
//        let cell = tableView.dequeue(GalleryCell.self)
//        return cell
        let cell = tableView.dequeueReusableCell(withIdentifier: "GalleryCell") as! GalleryCell?
        return cell!
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        super.tableView(tableView, willDisplay: cell, forRowAt: indexPath)
        guard let cell = cell as? GalleryCell else { return }

        let galleryItem = datasource[indexPath.row]

        let attributedLocality = NSMutableAttributedString(string: galleryItem.locality.uppercased(), attributes: [
//            NSAttributedString.Key.font: UIFont.robotoFont(ofSize: 22, weight: .medium),
            NSAttributedString.Key.kern: 8.2,
            NSAttributedString.Key.foregroundColor: UIColor.white,
        ])

        cell.topImageView?.image = UIImage(named: galleryItem.imageName)
        cell.localityLabel?.attributedText = attributedLocality
        cell.countryLabel?.text = galleryItem.country
        cell.aboutTitleLabel?.text = galleryItem.title
        cell.aboutDescriptionLabel?.text = galleryItem.description
    }
}
