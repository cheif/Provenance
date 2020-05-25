//
//  LegacyExtractor.swift
//  PVLibrary
//
//  Created by Dan Berglund on 2020-05-17.
//  Copyright © 2020 Provenance Emu. All rights reserved.
//

import Foundation
import PVSupport
import RxSwift
import RxCocoa
import ZipArchive

public protocol ReleaseIdChecker {
    func releaseID(forCRCs crcs: Set<String>) -> Int?
}

extension GameImporter: ReleaseIdChecker {}

public struct LegacyExtractor {
    private let releaseIdChecker: ReleaseIdChecker
    public init(releaseIdChecker: ReleaseIdChecker = GameImporter.shared) {
        self.releaseIdChecker = releaseIdChecker
    }

    enum Progress {
        case started(path: URL)
        case update(path: URL, entryNo: Int, total: Int, progress: Float)
        case finished(path: URL, files: [URL])
    }
    func extractArchive(at filePath: URL, to destination: URL) -> Observable<Progress> {
        if filePath.path.contains("MACOSX") {
            return .empty()
        }

        if !FileManager.default.fileExists(atPath: filePath.path) {
            WLOG("No file at \(filePath.path)")
            return .empty()
        }

        return Observable
            .just(filePath)
            .flatMap({ path -> Observable<Progress> in
                switch path.pathExtension.lowercased() {
                case "zip":
                    let events = SSZipArchive.rx.unzipFile(atPath: filePath.path, toDestination: destination.path, overwrite: true, password: nil).share()
                    let updates = events
                        .map { _, _, entryNo, total in Progress.update(path: filePath, entryNo: entryNo, total: total, progress: Float(entryNo) / Float(total)) }
                    let finished = events
                        .map { entry, _, _, _ in entry }
                        .filter { !$0.isEmpty }
                        .reduce([]) { acc, entry in acc + [filePath.appendingPathComponent(entry)]}
                        .map { Progress.finished(path: filePath, files: $0) }
                    return Observable.merge(updates, finished)
                case "7z":
                    let reader = LzmaSDKObjCReader(fileURL: filePath, andType: LzmaSDKObjCFileType7z)
                    let items = Observable.just(reader)
                        .do(onNext: { reader in try reader.open() })
                        .flatMap { reader in reader.rx.iterate() }
                        .reduce([]) { acc, item in acc + [item] }
                        .do(onNext: { items in
                            // TODO: Support natively using 7zips by matching crcs
                            let crcs = Set(items.filter({ $0.crc32 != 0 }).map { String($0.crc32, radix: 16, uppercase: true) })
                            if let releaseID = self.releaseIdChecker.releaseID(forCRCs: crcs) {
                                ILOG("Found a release ID \(releaseID) inside this 7Zip")
                            }
                        })
                        .share(replay: 1, scope: .forever)

                    let events = items
                        .flatMap { items in reader.rx.extract(items: items, toPath: destination.path, withFullPaths: false) }
                        .map { progress in Progress.update(path: filePath, entryNo: progress.entryNumber, total: Int(progress.total), progress: progress.progress) }
                    let updates = events

                    let finished = items
                        .map({ items -> [URL] in
                            items
                                .filter { !$0.isDirectory}
                                .compactMap { $0.fileName }
                                .map(destination.appendingPathComponent)
                        })
                        .map { Progress.finished(path: filePath, files: $0) }
                    return updates.concat(finished)
                default:
                    return .empty()
                }
            })
            .startWith(Progress.started(path: filePath))
            .do(onCompleted: {
                do {
                    try FileManager.default.removeItem(atPath: filePath.path)
                } catch {
                    ELOG("Unable to delete file at path \(filePath), because \(error.localizedDescription)")
                }
            })
    }
}

private extension Reactive where Base: SSZipArchive {
    typealias FileEventZip = (entry: String, zipInfo: unz_file_info, entryNumber: Int, total: Int)
    static func unzipFile(atPath path: String, toDestination destination: String, overwrite: Bool, password: String?) -> Observable<FileEventZip> {
        return Observable.create { observer in
            Base.unzipFile(atPath: path, toDestination: destination, overwrite: overwrite, password: password, progressHandler: { entry, zipInfo, entryNumber, total in
                observer.onNext((entry, zipInfo, entryNumber, total))
            }, completionHandler: { path, suceeded, error in
                if let error = error {
                    observer.onError(error)
                } else {
                    observer.onCompleted()
                }
            })
            return Disposables.create()
        }
    }
}

private extension Reactive where Base: LzmaSDKObjCReader {
    func iterate() -> Observable<LzmaSDKObjCItem> {
        Observable.create { observer in
            var keepIterating = true

            // This is synchronous, so it'll return when finished
            self.base.iterate { item, error -> Bool in
                if let error = error {
                    ELOG("7z error: \(error.localizedDescription)")
                } else {
                    observer.onNext(item)
                }
                // Continue iterating
                return keepIterating
            }
            observer.onCompleted()
            return Disposables.create {
                keepIterating = false
            }
        }
    }

    struct FileEvent7Zip: Equatable {
        let entryNumber: Int
        let total: UInt
        let progress: Float
    }
    func extract(items: [LzmaSDKObjCItem], toPath destination: String?, withFullPaths: Bool) -> Observable<FileEvent7Zip> {
        return Observable<Float>
            .create({ observer in
                let disposable = RxLzmaSDKObjCReaderDelegateProxy.proxy(for: self.base).extractProgress.bind(to: observer)
                self.base.extract(items, toPath: destination, withFullPaths: withFullPaths)
                return disposable
            })
            .map({ progress in
                let entryNumber = Int(floor(Float(self.base.itemsCount) * progress))
                return .init(entryNumber: entryNumber, total: self.base.itemsCount, progress: progress)
            })
            .distinctUntilChanged()
    }
}

private class RxLzmaSDKObjCReaderDelegateProxy: DelegateProxy<LzmaSDKObjCReader, LzmaSDKObjCReaderDelegate>, DelegateProxyType, LzmaSDKObjCReaderDelegate {
    static func registerKnownImplementations() {
        self.register { RxLzmaSDKObjCReaderDelegateProxy(parentObject: $0, delegateProxy: RxLzmaSDKObjCReaderDelegateProxy.self) }
    }

    static func currentDelegate(for object: LzmaSDKObjCReader) -> LzmaSDKObjCReaderDelegate? {
        return object.delegate
    }

    static func setCurrentDelegate(_ delegate: LzmaSDKObjCReaderDelegate?, to object: LzmaSDKObjCReader) {
        object.delegate = delegate
    }

    let extractProgress = PublishSubject<Float>()
    func onLzmaSDKObjCReader(_ reader: LzmaSDKObjCReader, extractProgress progress: Float) {
        if progress >= 1 {
            extractProgress.onCompleted()
        } else {
            extractProgress.onNext(progress)
        }
    }
}
