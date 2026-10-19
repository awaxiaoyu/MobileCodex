import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  func testNativeModelsUseStableIdentifiers() {
    let model = NativeModel(id: "gpt", label: "GPT", efforts: ["high"])
    XCTAssertEqual(model.id, "gpt")
  }

  func testTimelineProjectionGroupsMessagesByConsecutiveTurn() {
    let messages = [
      NativeMessage(id: "user-1", turnId: "turn-1", role: .user, text: "Inspect the project"),
      NativeMessage(id: "agent-1", turnId: "turn-1", role: .assistant, text: "I will inspect it."),
      NativeMessage(id: "user-2", turnId: "turn-2", role: .user, text: "Now summarize it."),
    ]

    let turns = NativeTimelineTurn.project(messages)

    XCTAssertEqual(turns.map(\.id), ["turn-1", "turn-2"])
    XCTAssertEqual(turns.map { $0.messages.map(\.id) }, [["user-1", "agent-1"], ["user-2"]])
  }
}
