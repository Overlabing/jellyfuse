import DesignSystem
import Foundation

/// The « Reprendre / Recommencer » choice offered before a playback that has a resume position. Every
/// entry point (billboard, « À suivre », detail, episodes) funnels through `PlayTarget`, so the decision
/// lives here once.
public struct PlayPrompt: Sendable, Equatable, Identifiable {
    public var id: String { resume.id }
    public let title: String
    /// `Reprendre à 0 h 12`.
    public let resumeLabel: String
    /// Plays from the saved position.
    public let resume: PlayTarget
    /// Same item from the beginning.
    public let restart: PlayTarget

    /// Nil when the target starts from the beginning anyway: it plays directly, without a question.
    public init?(_ target: PlayTarget) {
        guard target.resumeSeconds > 0, let position = MediaFormat.position(seconds: target.resumeSeconds) else { return nil }
        title = target.title
        resumeLabel = String(localized: "Reprendre à \(position)")
        resume = target
        restart = PlayTarget(id: target.id, title: target.title, resumeSeconds: 0)
    }
}
