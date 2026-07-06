import XCTest
@testable import ClipboardManager

final class TranslationServiceTests: XCTestCase {
    func testSanitizedModelOutputRemovesMultilineThinkingBlock() {
        let output = """
        <think>
        Analyze the source and choose the best wording.
        </think>
        最终翻译
        """

        XCTAssertEqual(TranslationService.sanitizedModelOutput(output), "最终翻译")
    }

    func testSanitizedModelOutputRemovesMultipleCaseInsensitiveBlocks() {
        let output = "<THINK>first</THINK>结果<think data-x='1'>second</think>"

        XCTAssertEqual(TranslationService.sanitizedModelOutput(output), "结果")
    }

    func testSanitizedModelOutputDropsUnclosedThinkingBlock() {
        let output = "最终结果\n<think>unfinished reasoning"

        XCTAssertEqual(TranslationService.sanitizedModelOutput(output), "最终结果")
    }
}
