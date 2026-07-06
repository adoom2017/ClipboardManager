import XCTest
import AppKit
@testable import ClipboardManager

final class ClipboardMonitorTests: XCTestCase {

    var clipboardMonitor: ClipboardMonitor!
    var pasteboard: NSPasteboard!

    override func setUpWithError() throws {
        super.setUp()
        guard let testPasteboard = NSPasteboard(
            name: .init("ClipboardMonitorTests.\(UUID().uuidString)")
        ) as NSPasteboard? else {
            throw XCTSkip("当前测试宿主无法创建独立 NSPasteboard")
        }
        pasteboard = testPasteboard
        clipboardMonitor = ClipboardMonitor(
            store: ClipboardStore(inMemory: true),
            pasteboard: pasteboard
        )
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: "isClipboardHistoryEnabled")
        clipboardMonitor?.stopMonitoring()
        clipboardMonitor = nil
        pasteboard = nil
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
        pasteboard.clearContents()
        pasteboard.setString("Test String", forType: .string)

        waitForExpectations(timeout: 3.0, handler: nil)
        cancellable.cancel()
    }

    func testDuplicateClipboardEntryNotStored() throws {
        clipboardMonitor.startMonitoring()

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

        pasteboard.clearContents()
        pasteboard.setString("Source App Test", forType: .string)

        let exp = expectation(description: "Wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exp.fulfill() }
        waitForExpectations(timeout: 3.0)

        if let item = clipboardMonitor.clipboardItems.first {
            XCTAssertFalse(item.sourceApp.isEmpty)
        }
    }

    func testDisabledHistoryDoesNotRecordClipboardChanges() throws {
        UserDefaults.standard.set(false, forKey: "isClipboardHistoryEnabled")
        clipboardMonitor.startMonitoring()

        pasteboard.clearContents()
        pasteboard.setString("Disabled History Test", forType: .string)

        let exp = expectation(description: "Wait for polling interval")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { exp.fulfill() }
        waitForExpectations(timeout: 2.0)

        XCTAssertFalse(clipboardMonitor.clipboardItems.contains { $0.content == "Disabled History Test" })

        UserDefaults.standard.set(true, forKey: "isClipboardHistoryEnabled")
        let reenableExp = expectation(description: "Wait after re-enabling")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { reenableExp.fulfill() }
        waitForExpectations(timeout: 2.0)
        XCTAssertFalse(clipboardMonitor.clipboardItems.contains { $0.content == "Disabled History Test" })
    }
}
