//
//  GalleryItem.swift
//  Campp
//
//  Created by Lingen Li on 2020/5/1.
//  Copyright © 2020 Apple. All rights reserved.
//

import Foundation

struct GalleryItem {

    let country: String
    let locality: String
    let description: String
    let title: String
    let imageName: String

    init(country: String, locality: String, description: String, title: String, imageName: String) {
        self.country = country
        self.locality = locality
        self.description = description
        self.title = title
        self.imageName = imageName
    }
}

extension GalleryItem {
    static var testData: [GalleryItem] {
        return [
            GalleryItem(country: "Swiss", locality: "Swiss Alps", description: "This residential project was recently completed by D4 Designs, a multi-award winning design practice founded in 2000 by Douglas Paton.", title: "Lingen's GalleryItem", imageName: "1"),
            GalleryItem(country: "France", locality: "Les Houches", description: "A special charm is given by the dark rectangular box above the main entrance.", title: "Lingen's GalleryItem", imageName: "4"),
            GalleryItem(country: "Austria", locality: "Vienna", description: "A wooden table and a beige stuffed couch in front of plasma, this is definitely a good place to spend your afternoons watching movies with your family.", title: "Lingen's GalleryItem", imageName: "7"),
            GalleryItem(country: "Australia", locality: "Sydney", description: "The team working on this project then became larger, also including collaborators Rios Clementi Hale Studios and designers Lorraine Letendre and Lynda Murray.", title: "Lingen's GalleryItem", imageName: "8"),
            GalleryItem(country: "Canada", locality: "Vancouver", description: "You can admire the beautiful landscape through large windows. This  area of the house stands out through the warmth color of the furniture.", title: "Lingen's GalleryItem", imageName: "6"),
            GalleryItem(country: "United States", locality: "Los Angeles", description: "The process of designing and then building a house usually start with a series of requests, a list of requirements coming from the client.", title: "Michael Bay's LA GalleryItem", imageName: "2"),
            GalleryItem(country: "Spain", locality: "Madrid", description: "With a bold façade and large outdoor spaces, this amazing house boasts personality and elegance.", title: "Lingen's GalleryItem", imageName: "3"),
            GalleryItem(country: "Japan", locality: "Tokyo", description: "The second floor incorporates an open living room, kitchen and dining room.", title: "Lingen's GalleryItem", imageName: "5"),
            GalleryItem(country: "Turkey", locality: "Didim", description: "The concept for the GalleryItem was originally created by Chad Oppenheim, the founder of the Oppenheim architecture firm.", title: "Lingen's GalleryItem", imageName: "9"),
        ]
    }
}
