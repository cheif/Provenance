//
//  DirectoryWatcher.swift
//  PVLibrary
//
//  Created by Dan Berglund on 2020-05-17.
//  Copyright © 2020 Provenance Emu. All rights reserved.
//

import Foundation
import PVSupport
import RxSwift

public final class DirectoryWatcher {
    public enum ExtractionEvent: Equatable {
        case started(path: URL)
        case updated(path: URL, progress: Float)
        case complete(path: URL, files: [URL])
        case failed(path: URL)

    }
    public enum Event: Equatable {
        case extraction(ExtractionEvent)
        case filesDetected(files: [URL])
    }

    public let events: Observable<Event>

    public init(directory: URL, extractor: LegacyExtractor = .init(), scheduler: SchedulerType = MainScheduler.asyncInstance) {
        let fileManager = FileManager.default
        let filesInDirectory = fileManager.rx.watchDirectory(at: directory, scheduler: scheduler)

        let rawRomsEvents: Observable<Event> = filesInDirectory
            .map { files in files.filter { !PVEmulatorConfiguration.archiveExtensions.contains($0.pathExtension) }}
            .map { .filesDetected(files: $0) }

        let extractionEvents: Observable<Event> = filesInDirectory
            .map { files in files.filter { PVEmulatorConfiguration.archiveExtensions.contains($0.pathExtension) }}
            .map { addedArchives in addedArchives.map { file in fileManager.rx.watchFile(at: file, scheduler: scheduler).asObservable() }}
            .flatMap(Observable.merge)
            .flatMap({ url in extractor.extractArchive(at: url, to: directory)
                .map({ event in
                    switch event {
                    case .started(let path):
                        return .extraction(.started(path: path))
                    case .update(let path, _, _, let progress):
                        return .extraction(.updated(path: path, progress: progress))
                    case .finished(let path, let files):
                        return .extraction(.complete(path: path, files: files))
                    }
                })
                .catchErrorJustReturn(.extraction(.failed(path: url)))
            })

        events = Observable.merge(rawRomsEvents, extractionEvents)
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
