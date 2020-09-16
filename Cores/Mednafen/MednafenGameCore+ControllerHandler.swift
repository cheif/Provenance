//
//  MednafenGameCore+ControllerHandler.swift
//  PVMednafen-iOS
//
//  Created by Dan Berglund on 2020-09-15.
//  Copyright © 2020 Provenance Emu. All rights reserved.
//

import Foundation
import PVSupport

extension MednafenGameCore: PVControllerHandler {
    public func handle(input: PVControllerInput, for player: Int) {
        let buffer = getInputBuffer(Int32(player))!
        switch input {
        case .button(let button, let isPressed):
            guard let offset = mapping.offset(for: button) else {
                WLOG("Unhandled button press: \(button)")
                return
            }
            let bitmap: UInt32 = 1 << offset
            if isPressed {
                buffer[0] |= bitmap
            } else {
                buffer[0] &= ~bitmap
            }
        }
    }

    private var mapping: Mapping.Type {
        switch systemType {
        case .PSX:
            return PSXMapping.self
        default:
            fatalError("Not implemented yet")
        }
    }
}

private protocol Mapping {
    static func offset(for button: PVControllerInput.Button) -> Int?
}

struct PSXMapping: Mapping {
    static func offset(for button: PVControllerInput.Button) -> Int? {
        return buttonMap[button]?.rawValue
    }

    private static let buttonMap: [PVControllerInput.Button: PSXButton] = [
        .up: .up,
        .down: .down,
        .left: .left,
        .right: .right,
        .a: .cross,
        .b: .circle,
        .x: .square,
        .y: .triangle,
        .leftShoulder: .l1,
        .leftTrigger: .l2,
        .L3: .l3,
        .rightShoulder: .r1,
        .rightTrigger: .r2,
        .R3: .r3
    ]

    private enum PSXButton: Int {
        case up = 4
        case down = 6
        case left = 7
        case right = 5
        case triangle = 12
        case circle = 13
        case cross = 14
        case square = 15
        case l1 = 10
        case l2 = 8
        case l3 = 1
        case r1 = 11
        case r2 = 9
        case r3 = 2
        case start = 3
        case select = 0
        case analogMode = 16
        case leftAnalogUp = 24
        case leftAnalogDown = 23
        case leftAnalogLeft = 22
        case leftAnalogRight = 21
        case rightAnalogUp = 20
        case rightAnalogDown = 19
        case rightAnalogLeft = 18
        case rightAnalogRight = 17
    }
}
