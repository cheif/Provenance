//
//  DirectoryWatcherTests.swift
//  PVLibraryTests
//
//  Created by Dan Berglund on 2020-05-21.
//  Copyright © 2020 Provenance Emu. All rights reserved.
//

import XCTest
import RxSwift
import RxTest
@testable import PVLibrary

class DirectoryWatcherTests: XCTestCase {
    static let folderPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    var bag: DisposeBag!
    var scheduler: TestScheduler!
    var sut: RxDirectoryWatcher!
    private let releaseIdChecker = ReleaseIdCheckerMock()
    let folderPath = DirectoryWatcherTests.folderPath
    let testZip = try! Data(contentsOf: Bundle(for: DirectoryWatcherTests.self).url(forResource: "test", withExtension: "zip")!)
    let test7Zip = try! Data(contentsOf: Bundle(for: DirectoryWatcherTests.self).url(forResource: "test", withExtension: "7z")!)

    override func setUp() {
        super.setUp()
        try! FileManager.default.createDirectory(at: folderPath, withIntermediateDirectories: true, attributes: nil)
        bag = .init()
        scheduler = .init(initialClock: 0)
        sut = .init(directory: folderPath, extractor: .init(releaseIdChecker: releaseIdChecker), scheduler: scheduler)
    }

    override func tearDown() {
        super.tearDown()
        bag = nil
        scheduler = nil
        sut = nil
        try! FileManager.default.removeItem(at: folderPath)
    }

    func testZipAlreadyAdded() {
        let archivePath = folderPath.appendingPathComponent("archive.zip")
        try! testZip.write(to: archivePath)

        let events = scheduler.start { self.sut.events }

        XCTAssertEqual(events.events, [
            .next(204, .extractionStarted(path: archivePath)),
            .next(204, .extractionUpdated(path: archivePath, progress: 0)),
            .next(204, .extractionUpdated(path: archivePath, progress: 0.5)),
            .next(204, .extractionComplete(path: archivePath))
        ])

        let files = try! FileManager.default.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil, options: []).map { $0.lastPathComponent }
        XCTAssertEqual(files, ["azure-pipelines.yml", "appcenter-post-clone.sh"])
    }

    func testAddingZip() {
        let archivePath = folderPath.appendingPathComponent("archive.zip")

        scheduler
            .createColdObservable([
                .next(203, (archivePath, testZip))
            ])
            .do(onNext: { url, data in
                try! data.write(to: url)
            })
            .subscribe()
            .disposed(by: bag)

        let events = scheduler.start { self.sut.events }

        XCTAssertEqual(events.events, [
            .next(206, .extractionStarted(path: archivePath)),
            .next(206, .extractionUpdated(path: archivePath, progress: 0)),
            .next(206, .extractionUpdated(path: archivePath, progress: 0.5)),
            .next(206, .extractionComplete(path: archivePath))
        ])

        let files = try! FileManager.default.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil, options: []).map { $0.lastPathComponent }
        XCTAssertEqual(files, ["azure-pipelines.yml", "appcenter-post-clone.sh"])
    }

    func testAdding7Zip() {
        let archivePath = folderPath.appendingPathComponent("archive.7z")

        scheduler
            .createColdObservable([
                .next(203, (archivePath, test7Zip))
            ])
            .do(onNext: { url, data in
                try! data.write(to: url)
            })
            .subscribe()
            .disposed(by: bag)

        let events = scheduler.start { self.sut.events }

        XCTAssertEqual(events.events, [
            .next(206, .extractionStarted(path: archivePath)),
            .next(206, .extractionUpdated(path: archivePath, progress: 0)),
            .next(206, .extractionComplete(path: archivePath))
        ])

        let files = try! FileManager.default.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil, options: []).map { $0.lastPathComponent }
        XCTAssertEqual(files, ["Provenance-Bridging-Header.h"])
    }

    func testAddingBrokenFile() {
        let zipPath = folderPath.appendingPathComponent("archive.zip")
        let archivePath = folderPath.appendingPathComponent("archive.7z")

        scheduler
            .createColdObservable([
                .next(203, (zipPath, test7Zip)),
                .next(250, (archivePath, test7Zip))
            ])
            .do(onNext: { url, data in
                try! data.write(to: url)
            })
            .subscribe()
            .disposed(by: bag)

        let events = scheduler.start { self.sut.events }

        XCTAssertEqual(events.events, [
            .next(206, .extractionStarted(path: zipPath)),
            .next(206, .extractionFailed(path: zipPath)),
            .next(254, .extractionStarted(path: archivePath)),
            .next(254, .extractionUpdated(path: archivePath, progress: 0)),
            .next(254, .extractionComplete(path: archivePath))
        ])

        let files = try! FileManager.default.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil, options: []).map { $0.lastPathComponent }
        XCTAssertEqual(files, ["Provenance-Bridging-Header.h", "archive.zip"])
    }

    func testStreamingwrite() {
        let archivePath = folderPath.appendingPathComponent("archive.zip")
        try! Data().write(to: archivePath)
        let handle = try! FileHandle(forWritingTo: archivePath)

        let chunks = (0...testZip.count/100).map { $0 * 100 }.map { offset in testZip.subdata(in: (offset..<min(testZip.endIndex, offset + 100))) }

        // Simulate writing 100bytes every other second
        scheduler
            .createColdObservable(
                chunks.enumerated().map { index, data in .next(200+index*2, data) }
        )
            .do(onNext: { data in
                handle.write(data)
            })
            .subscribe()
            .disposed(by: bag)

        let events = scheduler.start { self.sut.events }

        XCTAssertEqual(events.events, [
            .next(230, .extractionStarted(path: archivePath)),
            .next(230, .extractionUpdated(path: archivePath, progress: 0)),
            .next(230, .extractionUpdated(path: archivePath, progress: 0.5)),
            .next(230, .extractionComplete(path: archivePath))
        ])

        let files = try! FileManager.default.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil, options: []).map { $0.lastPathComponent }
        XCTAssertEqual(files, ["azure-pipelines.yml", "appcenter-post-clone.sh"])

    }
}

private struct ReleaseIdCheckerMock: ReleaseIdChecker {
    func releaseID(forCRCs crcs: Set<String>) -> Int? {
        nil
    }
}
