import XCTest
@testable import CamiFitApp

final class OnboardingFlowTests: XCTestCase {
    func testOnboardingStepsCoverCoreFeaturePillarsInOrder() {
        let steps = CamiFitOnboardingStep.all

        XCTAssertEqual(steps.map(\.id), [.movement, .engine, .coach, .memory, .privacy])
        XCTAssertEqual(Set(steps.map(\.id)).count, CamiFitOnboardingStepID.allCases.count)
        XCTAssertTrue(steps.allSatisfy { !$0.title.isEmpty && !$0.summary.isEmpty })
        XCTAssertTrue(steps.allSatisfy { $0.bullets.count >= 3 })

        print("onboarding-steps order=movement,engine,coach,memory,privacy count=\(steps.count)")
    }

    func testOnboardingCompletionIsVersionedForFirstLaunchFlow() {
        XCTAssertEqual(OnboardingCoordinator.completedStorageKey, "camifit.onboarding.completed")
        XCTAssertEqual(OnboardingCoordinator.completedVersionStorageKey, "camifit.onboarding.completedVersion")
        XCTAssertGreaterThanOrEqual(OnboardingCoordinator.currentVersion, 2)

        print("onboarding-versioned-completion version=\(OnboardingCoordinator.currentVersion)")
    }

    @MainActor
    func testOnboardingCoordinatorShowsAndDismissesTour() {
        let coordinator = OnboardingCoordinator()

        XCTAssertFalse(coordinator.isPresented)
        coordinator.showTour()
        XCTAssertTrue(coordinator.isPresented)
        coordinator.dismiss()
        XCTAssertFalse(coordinator.isPresented)

        print("onboarding-coordinator show=true dismiss=true")
    }
}
