//
//  ControlItemImageSet.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A named set of images that are used by control items.
///
/// An image set contains images for a control item in both the hidden and visible states.
nonisolated struct ControlItemImageSet: Codable, Hashable, Identifiable {
    enum Name: String, Codable, Hashable {
        case arrow = "Arrow"
        case chevron = "Chevron"
        case chevronDown = "Chevron (Down)"
        case door = "Door"
        case dot = "Dot"
        case ellipsis = "Ellipsis"
        case iceCube = "Ice Cube"
        case sunglasses = "Sunglasses"
        case foldCircle = "Circle"
        case foldLines = "Lines"
        case foldGrid = "Grid"
        case foldSparkle = "Sparkle"
        case foldTray = "Tray"
        case foldCapsule = "Pill"
        case custom = "Custom"

        /// Localized string key representation.
        var localized: LocalizedStringKey {
            switch self {
            case .arrow: "Arrow"
            case .chevron: "Chevron"
            case .chevronDown: "Chevron (Down)"
            case .door: "Door"
            case .dot: "Dot"
            case .ellipsis: "Ellipsis"
            case .iceCube: "Ice Cube"
            case .sunglasses: "Sunglasses"
            case .foldCircle: "Circle"
            case .foldLines: "Lines"
            case .foldGrid: "Grid"
            case .foldSparkle: "Sparkle"
            case .foldTray: "Tray"
            case .foldCapsule: "Pill"
            case .custom: "Custom"
            }
        }
    }

    let name: Name
    let hidden: ControlItemImage
    let visible: ControlItemImage

    var id: Int {
        hashValue
    }

    init(name: Name, hidden: ControlItemImage, visible: ControlItemImage) {
        self.name = name
        self.hidden = hidden
        self.visible = visible
    }

    init(name: Name, image: ControlItemImage) {
        self.init(name: name, hidden: image, visible: image)
    }
}

nonisolated extension ControlItemImageSet {
    /// The default image set for the Ice icon.
    static let defaultIceIcon = ControlItemImageSet(
        name: .chevronDown,
        hidden: .symbol("chevron.down"),
        visible: .symbol("chevron.up")
    )

    /// Extra sets offered by Fold's compact settings, ahead of Thaw's own.
    static let foldIcons = [
        defaultIceIcon,
        ControlItemImageSet(name: .foldCircle, hidden: .symbol("chevron.down.circle"), visible: .symbol("chevron.up.circle.fill")),
        ControlItemImageSet(name: .foldLines, hidden: .symbol("line.3.horizontal"), visible: .symbol("line.3.horizontal.decrease")),
        ControlItemImageSet(name: .foldGrid, hidden: .symbol("square.grid.2x2"), visible: .symbol("square.grid.2x2.fill")),
        ControlItemImageSet(name: .foldSparkle, hidden: .symbol("sparkle"), visible: .symbol("sparkles")),
        ControlItemImageSet(name: .foldTray, hidden: .symbol("tray"), visible: .symbol("tray.full")),
        ControlItemImageSet(name: .foldCapsule, hidden: .symbol("capsule"), visible: .symbol("capsule.fill")),
    ]

    /// The image sets that the user can choose to display in the Ice icon.
    static let userSelectableIceIcons = [
        ControlItemImageSet(
            name: .arrow,
            hidden: .symbol("arrowshape.left.fill"),
            visible: .symbol("arrowshape.right.fill")
        ),
        ControlItemImageSet(
            name: .chevron,
            hidden: .symbol("chevron.left"),
            visible: .symbol("chevron.right")
        ),
        ControlItemImageSet(
            name: .chevronDown,
            hidden: .symbol("chevron.down"),
            visible: .symbol("chevron.up")
        ),
        ControlItemImageSet(
            name: .door,
            hidden: .symbol("door.left.hand.closed"),
            visible: .symbol("door.left.hand.open")
        ),
        ControlItemImageSet(
            name: .dot,
            hidden: .catalog("DotFill"),
            visible: .catalog("DotStroke")
        ),
        ControlItemImageSet(
            name: .ellipsis,
            hidden: .catalog("EllipsisFill"),
            visible: .catalog("EllipsisStroke")
        ),
        ControlItemImageSet(
            name: .iceCube,
            hidden: .catalog("IceCubeStroke"),
            visible: .catalog("IceCubeFill")
        ),
        ControlItemImageSet(
            name: .sunglasses,
            hidden: .symbol("sunglasses.fill"),
            visible: .symbol("sunglasses")
        ),
    ]
}
