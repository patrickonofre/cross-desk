import Foundation
import Sparkle

/// Wrapper fino sobre o `SPUStandardUpdaterController` (Sparkle 2.x, SPM —
/// sparkle-auto-update). Sem `#if canImport(Sparkle)`/no-op como no
/// mac-metrics-view: lá o gate existe porque o mesmo código compila num alvo
/// Xcode (com o framework linkado) E num executável SPM à parte (`swift run`,
/// sem framework nenhum). Aqui `CrossDeskApp` é o único executável e é sempre
/// distribuído via `make-app.sh` — Sparkle está sempre presente, sem variante
/// sem ele pra suportar.
///
/// Subclasseia `NSObject` porque `SPUUpdaterDelegate`/`SPUStandardUserDriverDelegate`
/// herdam de `NSObjectProtocol`.
@MainActor
final class SparkleUpdateService: NSObject, SPUUpdaterDelegate {
    // Implicitly-unwrapped: built after super.init() so `self` can be the
    // delegate (SPUStandardUpdaterController takes delegates only at init,
    // SPUUpdater has no settable delegate property post-construction).
    private var controller: SPUStandardUpdaterController!

    /// Versão de uma atualização encontrada, ou `nil` quando não há nenhuma.
    /// Disparado tanto pela checagem passiva (`probeForUpdateInformation`,
    /// launch/periódica) quanto pela interativa — o `AppState` decide o que
    /// fazer com isso (rótulo discreto, R58).
    var onAvailableVersionChange: ((String?) -> Void)?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        controller.startUpdater()
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    /// Checagem interativa (botão "Verificar Atualizações" / "Instalar") — o
    /// Sparkle assume com a UI dele: download, verificação EdDSA, troca do
    /// bundle e relaunch.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    /// Checagem passiva (launch/periódica via `SUScheduledCheckInterval`) —
    /// sem UI, só reporta via `onAvailableVersionChange`.
    func probeForUpdateInformation() {
        controller.updater.checkForUpdateInformation()
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        onAvailableVersionChange?(version.isEmpty ? nil : version)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        onAvailableVersionChange?(nil)
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension SparkleUpdateService: @preconcurrency SPUStandardUserDriverDelegate {
    /// Checagens automáticas (launch/24h) não devem estourar a UI do Sparkle
    /// na cara do usuário — só o rótulo discreto do `MenuBarView` (R58/P2).
    /// A UI completa só aparece quando o usuário mesmo pede
    /// (`checkForUpdates()`, botão).
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }
}
