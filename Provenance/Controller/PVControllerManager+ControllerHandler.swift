//
//  PVControllerManager+ControllerHandler.swift
//  Provenance
//
//  Created by Dan Berglund on 2020-09-16.
//  Copyright © 2020 Provenance Emu. All rights reserved.
//

import Foundation
import RxSwift

extension PVControllerManager {
    var controllerEvents: Observable<(PVControllerInput, Int)> {
        Observable.merge([
            player1?.controllerEvents?.map { ($0, 0) },
            player2?.controllerEvents?.map { ($0, 1) },
            player3?.controllerEvents?.map { ($0, 2) },
            player4?.controllerEvents?.map { ($0, 3) }
            ].compactMap { $0 }
        )
    }
}

private extension GCController {
    var controllerEvents: Observable<PVControllerInput>? {
        return extendedGamepad?.controllerEvents ??
            microGamepad?.controllerEvents
    }
}

private extension GCMicroGamepad {
    var controllerEvents: Observable<PVControllerInput> {
        Observable.merge([
            dpad.up.isPressedValue.map { .button(.up, isPressed: $0) },
            dpad.down.isPressedValue.map { .button(.down, isPressed: $0) },
            dpad.left.isPressedValue.map { .button(.left, isPressed: $0) },
            dpad.right.isPressedValue.map { .button(.right, isPressed: $0) },
            buttonA.isPressed.map { .button(.a, isPressed: $0) },
            buttonX.isPressed.map { .button(.x, isPressed: $0) }
        ])
    }
}

private extension GCExtendedGamepad {
    var controllerEvents: Observable<PVControllerInput> {
        var observables: [Observable<PVControllerInput>] = [
            dpad.up.isPressed.map { .button(.up, isPressed: $0) },
            dpad.down.isPressed.map { .button(.down, isPressed: $0) },
            dpad.left.isPressed.map { .button(.left, isPressed: $0) },
            dpad.right.isPressed.map { .button(.right, isPressed: $0) },
            buttonA.isPressed.map { .button(.a, isPressed: $0) },
            buttonB.isPressed.map { .button(.b, isPressed: $0) },
            buttonX.isPressed.map { .button(.x, isPressed: $0) },
            buttonY.isPressed.map { .button(.y, isPressed: $0) },
            leftShoulder.isPressed.map { .button(.leftShoulder, isPressed: $0) },
            leftTrigger.isPressed.map { .button(.leftTrigger, isPressed: $0) },
            rightShoulder.isPressed.map { .button(.rightShoulder, isPressed: $0) },
            rightTrigger.isPressed.map { .button(.rightTrigger, isPressed: $0) },
        ]

        if #available(tvOS 12.1, *) {
            observables += [
                leftThumbstickButton?.isPressed.map { .button(.L3, isPressed: $0) },
                rightThumbstickButton?.isPressed.map { .button(.R3, isPressed: $0) }
                ].compactMap { $0 }
        }
        return Observable.merge(observables)
    }
}

private extension GCControllerButtonInput {
    var isPressed: Observable<Bool> {
        .create { observer in
            self.pressedChangedHandler = { (_, _, isPressed: Bool) in
                observer.onNext(isPressed)
            }

            return Disposables.create {
                self.pressedChangedHandler = nil
            }
        }
    }

    var isPressedValue: Observable<Bool> {
        .create { observer in
            self.valueChangedHandler = { (_, value: Float, _) in
                observer.onNext(value > 0.5)
            }

            return Disposables.create {
                self.valueChangedHandler = nil
            }
        }
    }
}
