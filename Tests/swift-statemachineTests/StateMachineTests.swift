import XCTest
@testable import swift_statemachine

class StateMachineTests: XCTestCase {

	enum TestState: State {
		case initial
		case first
		case second
	}

	enum TestEvent: Event {
		case initialToFirst
		case firstToSecond
	}

	var semaphore1 = false
	var semaphore2 = false
	let stateChangeHandlerCalledExpectation = XCTestExpectation(description: "stateChangeHandlerCalled")
	let errorHandlerCalledExpectation = XCTestExpectation(description: "errorHandlerCalled")

	var stateMachine: StateMachine<TestState, TestEvent>?

    override func setUp() {
        stateMachine = StateMachine<TestState, TestEvent>(initialState: .initial, initClosure:  { machine in
            machine.addRoute(forEvent: .initialToFirst, transition: .initial => .first)
            machine.addRoute(forEvent: .firstToSecond,
                             route: StateMachine<TestState, TestEvent>.Route(
                                transition: .first => .second,
                                postBlock: nil,
                                conditions: [ { transition in
                                    return transition == Transition<TestState>(fromState: .first, toState: .second)
                                }, { _ in
                                    return self.semaphore1
                                },
                                self.testCondition
                                ])
            )
            machine.stateChangeHandler = self.onStateChange
            machine.errorHandler = self.errorHandler
        })
		stateMachine?.start()
	}

    override func tearDown() {
		stateMachine = nil
	}

    func testSimpleTransition() {
		stateMachine!.tryEvent(.initialToFirst)
		XCTAssertTrue(stateMachine!.state == .first)
    }

    func testConditionalTransition() {
		if stateMachine?.state == .initial {
			stateMachine?.tryEvent(.initialToFirst)
		}
		stateMachine!.tryEvent(.firstToSecond)

		XCTAssertFalse(stateMachine!.state == .second)
		semaphore1 = true
		stateMachine!.tryEvent(.firstToSecond)
		XCTAssertTrue(stateMachine!.state == .second)
		wait(for: [stateChangeHandlerCalledExpectation], timeout: 1.0)
    }

	func testInvalidTransition() {
		if stateMachine!.state == .initial {
			stateMachine!.tryEvent(.initialToFirst)
			semaphore1 = true
			stateMachine!.tryEvent(.firstToSecond)
		}
		XCTAssertTrue(stateMachine!.state == .second)
		stateMachine?.tryEvent(.initialToFirst)
		XCTAssertTrue(stateMachine!.state == .second)
		wait(for: [errorHandlerCalledExpectation], timeout: 1.0)
	}
}

extension StateMachineTests {
	func testCondition(transition: Transition<TestState>) -> Bool {
		semaphore2 = true
		return semaphore2
	}

	func onStateChange(fromState: TestState, toState: TestState, userInfo: Any?) {
		stateChangeHandlerCalledExpectation.fulfill()
	}

	func errorHandler(event: TestEvent, state: TestState) {
		errorHandlerCalledExpectation.fulfill()
	}
}
