//
//  DirectoryWatcherTests.swift
//  PVLibraryTests
//
//  Created by Dan Berglund on 2020-05-21.
//  Copyright © 2020 Provenance Emu. All rights reserved.
//

import XCTest
@testable import PVLibrary

class DirectoryWatcherTests: XCTestCase {
    static let folderPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    var sut: DirectoryWatcher!
    private let releaseIdChecker = ReleaseIdCheckerMock()
    let folderPath = DirectoryWatcherTests.folderPath
    let testZip = try! Data(contentsOf: Bundle(for: DirectoryWatcherTests.self).url(forResource: "test", withExtension: "zip")!)
    let test7Zip = try! Data(contentsOf: Bundle(for: DirectoryWatcherTests.self).url(forResource: "test", withExtension: "7z")!)

    override func setUp() {
        super.setUp()
        try! FileManager.default.createDirectory(at: folderPath, withIntermediateDirectories: true, attributes: nil)
    }

    override func tearDown() {
        super.tearDown()
        sut.stopMonitoring()
        try! FileManager.default.removeItem(at: folderPath)
    }

    func testZipAlreadyAdded() {
        let exp = expectation(description: "Test")
        sut = .init(directory: folderPath, extractionStartedHandler: nil, extractionUpdatedHandler: nil, extractionCompleteHandler: { urls in
            XCTAssertEqual(urls?.count, 2)
            exp.fulfill()
        }, releaseIdChecker: releaseIdChecker)

        try! testZip.write(to: folderPath.appendingPathComponent("archive.zip"))
        sut.startMonitoring()

        wait(for: [exp], timeout: 4.0)
        let files = try! FileManager.default.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil, options: []).map { $0.lastPathComponent }
        XCTAssertEqual(files, ["azure-pipelines.yml", "appcenter-post-clone.sh"])
    }

    func testAddingZip() {
        let exp = expectation(description: "Test")
        sut = .init(directory: folderPath, extractionStartedHandler: nil, extractionUpdatedHandler: nil, extractionCompleteHandler: { urls in
            XCTAssertEqual(urls?.count, 2)
            exp.fulfill()
        }, releaseIdChecker: releaseIdChecker)

        sut.startMonitoring()
        try! testZip.write(to: folderPath.appendingPathComponent("archive.zip"))

        wait(for: [exp], timeout: 4.0)
        let files = try! FileManager.default.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil, options: []).map { $0.lastPathComponent }
        XCTAssertEqual(files, ["azure-pipelines.yml", "appcenter-post-clone.sh"])
    }

    func testAdding7Zip() {
        let exp = expectation(description: "Test")
        sut = .init(directory: folderPath, extractionStartedHandler: nil, extractionUpdatedHandler: nil, extractionCompleteHandler: { urls in
        XCTAssertEqual(urls?.count, 1)
            exp.fulfill()
        }, releaseIdChecker: releaseIdChecker)

        sut.startMonitoring()
        try! test7Zip.write(to: folderPath.appendingPathComponent("archive.7z"))

        wait(for: [exp], timeout: 4.0)
        let files = try! FileManager.default.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil, options: []).map { $0.lastPathComponent }
        XCTAssertEqual(files, ["Provenance-Bridging-Header.h"])
    }

    func testAddingBrokenFile() {
        let exp = expectation(description: "Test")
        sut = .init(directory: folderPath, extractionStartedHandler: nil, extractionUpdatedHandler: nil, extractionCompleteHandler: { urls in
        XCTAssertEqual(urls?.count, 1)
            exp.fulfill()
        }, releaseIdChecker: releaseIdChecker)

        sut.startMonitoring()
        try! Data(base64Encoded: "")!.write(to: folderPath.appendingPathComponent("archive.zip"))
        try! test7Zip.write(to: folderPath.appendingPathComponent("archive.7z"))

        wait(for: [exp], timeout: 4.0)
        let files = try! FileManager.default.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil, options: []).map { $0.lastPathComponent }
        XCTAssertEqual(files, ["Provenance-Bridging-Header.h", "archive.zip"])
    }
}

private struct ReleaseIdCheckerMock: ReleaseIdChecker {
    func releaseID(forCRCs crcs: Set<String>) -> Int? {
        nil
    }
}
