//
//  RxDirectoryWatcher.swift
//  PVLibrary
//
//  Created by Dan Berglund on 2020-05-17.
//  Copyright © 2020 Provenance Emu. All rights reserved.
//

import Foundation
import PVSupport
import RxSwift

public final class RxDirectoryWatcher {
    public enum Event: Equatable {
        case extractionStarted(path: URL)
        case extractionUpdated(path: URL, progress: Float)
        case extractionComplete(path: URL)
        case extractionFailed(path: URL)
    }

    public let events: Observable<Event>

    init(directory: URL, extractor: LegacyExtractor = .init(), scheduler: SchedulerType = MainScheduler.asyncInstance) {
        let fileManager = FileManager.default
        let updatedFiles = fileManager.rx.watchDirectory(at: directory, scheduler: scheduler)
            .map { addedFiles in addedFiles.map { file in fileManager.rx.watchFile(at: file, scheduler: scheduler).asObservable() }}
            .flatMap(Observable.merge)

        events = updatedFiles
            .flatMap({ url in extractor.extractArchive(at: url, to: directory)
                .map({ event in
                    switch event {
                    case .started(let path):
                        return .extractionStarted(path: path)
                    case .update(let path, _, _, let progress):
                        return .extractionUpdated(path: path, progress: progress)
                    case .finished(let path, _):
                        return .extractionComplete(path: path)
                    }
                })
                .catchErrorJustReturn(.extractionFailed(path: url))
            })
    }
}

private extension Reactive where Base: FileManager {
    func watchDirectory(at path: URL, scheduler: SchedulerType) -> Observable<[URL]> {
        DLOG("Start Monitoring \(path.path)")

        return Observable<Int>.timer(.seconds(0), period: .seconds(2), scheduler: scheduler)
            .map { _ in try self.base.contentsOfDirectory(at: path, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) }
            .catchError { _ in .never()}
            .map(Set.init)
            .scan((current: Set(), updated: Set()), accumulator: { acc, current in
                (
                    current: current,
                    updated: current.subtracting(acc.current)
                )
            })
            .map({ $0.updated
                // Ignore special files
                .filter { !$0.lastPathComponent.starts(with: ".") && !$0.path.contains("_MACOSX") }
            })
            .filter { !$0.isEmpty }
    }

    func watchFile(at path: URL, scheduler: SchedulerType) -> Maybe<URL> {
        if !PVEmulatorConfiguration.archiveExtensions.contains(path.pathExtension) {
            return .empty()
        }
        DLOG("Start watching \(path.lastPathComponent)")

        let sizes: Observable<UInt64> = Observable<Int>
            .timer(.seconds(0), period: .seconds(2), scheduler: scheduler)
            .map { _ in try? self.base.attributesOfItem(atPath: path.path)[FileAttributeKey.size] as? UInt64 }
            .map { $0 ?? 0 }
        return sizes
            .scan((nil, nil)) { acc, curr in (acc.1, curr) }
            .flatMap({ acc -> Observable<(UInt64?, UInt64)> in
                guard let current = acc.1 else { return .never() }
                return .just((acc.0, current))
            })
            .flatMap({ previous, current -> Maybe<URL> in
                let sizeHasntChanged = previous == current
                if sizeHasntChanged && current > 0 {
                    return .just(path)
                } else {
                    return .never()
                }
            })
            .take(1)
            .asMaybe()
    }
}
