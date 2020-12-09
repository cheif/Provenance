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
        case .analog(let stick, let xValue, let yValue):
            let supportsAnalogMode = mapping.supportsAnalogMode(with: buffer[0])
            if !supportsAnalogMode && stick == .left {
                // Analog mode is a PSX-only feature, if it's not enabled, or we're not on PSX, we handle the left stick as a dpad
                handle(input: .button(.up, isPressed: yValue > 0), for: player)
                handle(input: .button(.down, isPressed: yValue < 0), for: player)
                handle(input: .button(.left, isPressed: xValue < 0), for: player)
                handle(input: .button(.right, isPressed: xValue > 0), for: player)
            } else if supportsAnalogMode,
                let (xOffset, yOffset) = mapping.offset(for: stick) {
                // TODO
                // Fix the analog circle-to-square axis range conversion by scaling between a value of 1.00 and 1.50
                // We cannot use MDFNI_SetSetting("psx.input.port1.dualshock.axis_scale", "1.33") directly.
                // Background: https://mednafen.github.io/documentation/psx.html#Section_analog_range
                // double scaledValue = MIN(floor(0.5 + value * 1.33), 32767); // 30712 / cos(2*pi/8) / 32767 = 1.33

                // We scale the -1.0 -> 1.0 values to the PSX space, which is 0 -> UInt16.maxValue (65535), where 32767 means the stick is in the center
                let mappedXValue = UInt16(Int32(32767) + Int32(xValue * 32767))
                // y-axis is inverted on PSX
                let mappedYValue = UInt16(Int32(32767) + Int32(-yValue * 32767))

                buffer.withMemoryRebound(to: UInt8.self, capacity: 8, { u8Pointer in
                    self.mdnf_en16lsb(u8Pointer + xOffset, withValue: mappedXValue)
                    self.mdnf_en16lsb(u8Pointer + yOffset, withValue: mappedYValue)
                })
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

    static func supportsAnalogMode(with inputBuffer: UInt32) -> Bool
    static func offset(for stick: PVControllerInput.Stick) -> (xAxis: Int, yAxis: Int)?
}

extension Mapping {
    static func supportsAnalogMode(with inputBuffer: UInt32) -> Bool {
        false
    }

    static func offset(for stick: PVControllerInput.Stick) -> (xAxis: Int, yAxis: Int)? {
        nil
    }
}

struct PSXMapping: Mapping {
    static var supportsAnalogMode: Bool { true }
    static func offset(for button: PVControllerInput.Button) -> Int? {
        return buttonMap[button]?.rawValue
    }

    static func supportsAnalogMode(with inputBuffer: UInt32) -> Bool {
        // Check if analogMode-bit is set
        (inputBuffer & (1 << 17)) != 0
    }

    static func offset(for stick: PVControllerInput.Stick) -> (xAxis: Int, yAxis: Int)? {
        switch stick {
        case .left:
            return (xAxis: 7, yAxis: 9)
        case .right:
            return (xAxis: 3, yAxis: 5)
        }
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
