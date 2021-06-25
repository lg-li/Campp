//
//  GalleryDetailedViewController.swift
//  Campp
//
//  Created by Lingen Li on 2020/5/1.
//  Copyright © 2020 Apple. All rights reserved.
//

import ElongationPreview
import UIKit

final class GalleryDetailViewController: ElongationDetailViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .black
        tableView.separatorStyle = .none
        tableView.register(UINib(nibName: "GalleryCell", bundle: nil), forCellReuseIdentifier: "GalleryCell")
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt _: IndexPath) -> UITableViewCell {
//        let cell = tableView.dequeue(GridViewCell.self);
        let cell = tableView.dequeueReusableCell(withIdentifier: "GalleryCell") as! GalleryCell?
        return cell!
    }

    override func tableView(_: UITableView, heightForRowAt _: IndexPath) -> CGFloat {
        let appearance = ElongationConfig.shared
        let headerHeight = appearance.topViewHeight + appearance.bottomViewHeight
        let screenHeight = UIScreen.main.bounds.height
        return screenHeight - headerHeight
    }
}
