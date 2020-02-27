// Remove once Help is removed from here


typealias OMG = String

let x = [String: String]()

func foo() {}

final class TripDetailsComponent: PluginizedComponent<TripDetailsDependency, TripDetailsPluginExtension, TripDetailsNonCoreComponent> {
    private var interactor: UserIdentityFlow.IdentityVerificationIntroInteractor!

    private let presenter = UserIdentityFlow.IdentityVerificationIntroPresentableMock()
}

let rewardsBottomButtonFactoryCreateButtonHandler: ((_ analyticsID: AnalyticsID, _ themeStream: ThemeStream) -> RewardsBottomButton)? = { (_, _) -> RewardsBottomButton in
    let rewardsBottomButtonMock = RewardsBottomButtonMock(button: Button__Deprecated(analyticsID: .value("test"), themeStream: StaticThemeStream.forHelix))
    rewardsBottomButtonMock.installHandler = { view in
        view.addSubview(rewardsBottomButtonMock.button)

        let make = rewardsBottomButtonMock.button.snp.beginRemakingConstraints()
        make.leading.trailing.bottom.equalToSuperview()
        make.endRemakingConstraints()
    }
    rewardsBottomButtonMock.getControlHandler = {
        return rewardsBottomButtonMock.button
    }
    return rewardsBottomButtonMock
}
