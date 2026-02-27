import XCTest
import AppKit
@testable import ClipboardManager

final class ClipboardMonitorTests: XCTestCase {

    var clipboardMonitor: ClipboardMonitor!

    override func setUpWithError() throws {
        super.setUp()
        clipboardMonitor = ClipboardMonitor()
    }

    override func tearDownWithError() throws {
        clipboardMonitor.stopMonitoring()
        clipboardMonitor = nil
        super.tearDown()
    }

    func testClipboardChangeDetection() throws {
        let expectation = self.expectation(description: "Clipboard change detected")

        clipboardMonitor.startMonitoring()

        // 监听 newClipboardContent 变化
        let cancellable = clipboardMonitor.$newClipboardContent
            .compactMap { $0 }
            .sink { item in
                XCTAssertFalse(item.content.isEmpty)
                expectation.fulfill()
            }

        // 写入剪贴板触发检测
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Test String", forType: .string)

        waitForExpectations(timeout: 3.0, handler: nil)
        cancellable.cancel()
    }

    func testDuplicateClipboardEntryNotStored() throws {
        clipboardMonitor.startMonitoring()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Duplicate Test", forType: .string)

        // 等待监控器检测
        let exp = expectation(description: "Wait for monitor")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 3.0)

        let count = clipboardMonitor.clipboardItems.filter { $0.content == "Duplicate Test" }.count
        XCTAssertEqual(count, 1, "粗复内容不应重复记录")
    }

    func testSourceAppRetrieval() throws {
        clipboardMonitor.startMonitoring()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Source App Test", forType: .string)

        let exp = expectation(description: "Wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exp.fulfill() }
        waitForExpectations(timeout: 3.0)

        if let item = clipboardMonitor.clipboardItems.first {
            XCTAssertFalse(item.sourceApp.isEmpty)
        }
    }
}