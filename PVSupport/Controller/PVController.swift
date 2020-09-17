//
//  PVController.swift
//  Provenance
//
//  Created by Dan Berglund on 2020-09-15.
//  Copyright © 2020 Provenance Emu. All rights reserved.
//

import Foundation

public enum PVControllerInput {
    case button(Button, isPressed: Bool)
    case analog(Stick, xValue: Float, yValue: Float)

    public enum Button {
        case up
        case down
        case left
        case right
        case a
        case b
        case x
        case y
        case leftShoulder
        case leftTrigger
        case L3
        case rightShoulder
        case rightTrigger
        case R3
    }

    public enum Stick {
        case left
        case right
    }
}

public protocol PVControllerHandler {
    func handle(input: PVControllerInput, for player: Int)
}
