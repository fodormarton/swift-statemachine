import Foundation

public protocol State: Hashable, CaseIterable {}
public protocol Event: Hashable {}

public struct Transition<S: State>: Hashable {
	public let fromState: S
	public let toState: S

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fromState)
        hasher.combine(toState)
    }

	public static func ==(lhs: Transition, rhs: Transition) -> Bool {
		return lhs.fromState == rhs.fromState && lhs.toState == rhs.toState
	}
}

public final class StateMachine<S: State, E: Event> {

	/// Closure for validating transition.
	/// If condition returns `false`, transition will fail and associated handlers will not be invoked.
    public typealias Conditions = [Condition]
	public typealias Condition = (Transition<S>) -> Bool

	/// Transition callback invoked when state has been changed successfully.
	public typealias ErrorHandler = (E, S) -> Void
	public typealias Handler = (S, S, Any?) -> Void

    public typealias TransitionPostBlock = ((E, S, S) -> Void)
	public struct Route {
		public let transition: Transition<S>
        public let postBlock: TransitionPostBlock?
		public let conditions: [Condition]?

		internal func isPassingConditions(fromState: S, toState: S) -> Bool {
			guard transition == Transition(fromState: fromState, toState: toState) else { return false }
			guard let conditions = conditions else { return true }

			for condition in conditions {
				if !condition(transition) { return false }
			}
			return true
		}
	}

	//--------------------------------------------------
	// MARK: - Storage
	//--------------------------------------------------
	public private(set) var state: S

	private lazy var routes = [E: [Route]]()
	public var stateChangeHandler: Handler? {
		didSet {
            if initialized {
                stateChangeHandler?(state, state, nil)
            }
		}
	}
	public var errorHandler: ErrorHandler?
	private var initialized = false
	private var started = false

	//--------------------------------------------------
	// MARK: - Init
	//--------------------------------------------------

	public init(initialState: S, stateChangeHandler: Handler? = nil, initClosure: ((StateMachine) -> Void)? = nil) {
		self.state = initialState
		self.stateChangeHandler = stateChangeHandler
		initClosure?(self)
        self.initialized = true
	}

	public func configure(_ closure: (StateMachine) -> Void) {
		closure(self)
	}

    public func start() {
		started = true
        stateChangeHandler?(state, state, nil)
    }

	//--------------------------------------------------
	// MARK: - Route
	//--------------------------------------------------

    public func addRoutes(forEvent event: E, fromStates: [S], toState: S, postBlock: TransitionPostBlock? = nil, conditions: Conditions? = nil) {
        for fromState in fromStates {
            addRoute(forEvent: event, fromState: fromState, toState: toState, postBlock: postBlock, conditions: conditions)
        }
    }

    public func addRoutes(forEvent event: E, fromAnyStateToState toState: S, postBlock: TransitionPostBlock? = nil, conditions: Conditions? = nil) {
        for fromState in S.allCases {
            addRoute(forEvent: event, fromState: fromState, toState: toState, postBlock: postBlock, conditions: conditions)
        }
    }

    public func addRoute(forEvent event: E, fromState: S, toState: S, postBlock: TransitionPostBlock? = nil, conditions: Conditions? = nil) {
        addRoute(forEvent: event, transition: fromState => toState, postBlock: postBlock, conditions: conditions)
    }

    public func addRoute(forEvent event: E, transition: Transition<S>, postBlock: TransitionPostBlock? = nil, conditions: Conditions? = nil) {
        addRoute(forEvent: event, route: Route(transition: transition, postBlock: postBlock, conditions: conditions))
	}

	public func addRoute(forEvent event: E, route: Route) {
		routes[event, default: []].append(route) //Uniqueing?
	}

	//--------------------------------------------------
	// MARK: - hasRoute
	//--------------------------------------------------

	private func hasRoute(forEvent event: E, transition: Transition<S>) -> Bool {
		return self.hasRoute(forEvent: event, fromState: transition.fromState, toState: transition.toState)
	}

	private func hasRoute(forEvent event: E, fromState: S, toState: S) -> Bool {
		guard let allRoutes = routes[event] else { return false }
		return allRoutes.contains(where: { $0.isPassingConditions(fromState: fromState, toState: toState) })
	}

	//--------------------------------------------------
	// MARK: - tryEvent
	//--------------------------------------------------

	public func passingRouteForEvent(_ event: E) -> Route? {
		guard let allRoutes = routes[event] else { return nil }
		return allRoutes.first(where: { $0.isPassingConditions(fromState: state, toState: $0.transition.toState) })
	}

	@discardableResult
    public func tryEvent(_ event: E, userInfo: Any? = nil, triggerHandler: Bool = true) -> Bool {
		guard initialized, started else { return false }

        let fromState = state
		if let route = passingRouteForEvent(event) {
            state = route.transition.toState
            route.postBlock?(event, fromState, state)
            if triggerHandler {
                stateChangeHandler?(fromState, state, userInfo)
            }
			return true
		} else {
			errorHandler?(event, fromState)
			return false
		}
	}
}

//--------------------------------------------------
// MARK: - Custom Operators
//--------------------------------------------------

// MARK: `<-!` (tryEvent)
infix operator <-! : AdditionPrecedence

public func <-! <S: State, E: Event>(machine: StateMachine<S, E>, event: E) {
	machine.tryEvent(event)
}

// MARK: - Convenienve Transition initializer
infix operator => : AdditionPrecedence

public func => <S>(left: S, right: S) -> Transition<S> {
	return Transition(fromState: left, toState: right)
}

// MARK: - Debug description
extension Transition: CustomDebugStringConvertible {
	public var debugDescription: String {
		return "\(fromState) => \(toState)"
	}
}
