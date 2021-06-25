//
//  GalleryCell.swift
//  Campp
//
//  Created by Lingen Li on 2020/5/1.
//  Copyright © 2020 Apple. All rights reserved.
//

import ElongationPreview
import UIKit

final class GalleryCell: ElongationCell {

    @IBOutlet var topImageView: UIImageView!
    @IBOutlet var localityLabel: UILabel!
    @IBOutlet var countryLabel: UILabel!

    @IBOutlet var aboutTitleLabel: UILabel!
    @IBOutlet var aboutDescriptionLabel: UILabel!

    @IBOutlet var topImageViewTopConstraint: NSLayoutConstraint!
}
