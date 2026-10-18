import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  func testNativeModelsUseStableIdentifiers() {
    let model = NativeModel(id: "gpt", label: "GPT", efforts: ["high"])
    XCTAssertEqual(model.id, "gpt")
  }
}
