//! Tests for shared adversarial match play: the pure outcome/summary helpers and
//! real head-to-head + tournament runs over the case's committed baselines.

use std::path::PathBuf;

use foray_core::board::Team;

use super::*;
use test_cabinet_contracts::engine::NONE_SLUG;
use test_cabinet_contracts::test_case::{
    AssetDimension, AssetKind, BuildCommands, ContractSpec, EngineSupport, SandboxSpec,
    SimulationSpec, TestCaseVersion, TestType,
};

/// A copy of the committed Foray case's baselines: the `references/*.wasm` every
/// match below is played between.
fn case_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("testdata/foray")
}

/// A Foray version rooted at the real case, with a low `max_ticks` so a match
/// resolves quickly even when neither baseline sweeps.
fn foray_version(max_ticks: u32) -> TestCaseVersion {
    TestCaseVersion {
        toolchain: None,
        instrumentation: None,
        slug: "foray".to_string(),
        version: "v1.0.0".to_string(),
        experimental: false,
        engine_format: false,
        name: "Foray".to_string(),
        difficulty: "hard".to_string(),
        tags: Vec::new(),
        summary: None,
        description_path: None,
        changelog_path: std::path::PathBuf::new(),
        root: case_root(),
        prompt_path: PathBuf::from("prompt.hbs"),
        max_runtime_seconds: 1800,
        test_type: TestType::Adversarial,
        build: Some(BuildCommands {
            install: "cargo fetch".to_string(),
            build: "cargo build".to_string(),
            module: Some(PathBuf::from(
                "target/wasm32-unknown-unknown/release/controller.wasm",
            )),
        }),
        canvas: None,
        tool: None,
        output: None,
        contract: Some(ContractSpec {
            entry: "tick".to_string(),
            world: Some(PathBuf::from("schemas/world.json")),
            action: Some(PathBuf::from("schemas/action.json")),
            input: None,
            output: None,
        }),
        sandbox: Some(SandboxSpec {
            fuel_per_tick: Some(5_000_000),
            fuel_limit: None,
            max_memory_bytes: 67_108_864,
        }),
        simulation: Some(SimulationSpec {
            timestep_ms: 16,
            max_ticks,
        }),
        r#match: None,
        replay: None,
        asset_kind: AssetKind::Sprite,
        asset_dimension: AssetDimension::TwoD,
        sheet: None,
        voxel: None,
        model: None,
        ui: None,
        material: None,
        particle: None,
        audio: None,
        audio_packs: Vec::new(),
        common_specs: Vec::new(),
        common_workspace: Default::default(),
        init: None,
        asset_paths: Vec::new(),
        packages: Vec::new(),
        engines: vec![EngineSupport::unbounded(NONE_SLUG)],
        variants: Vec::new(),
        common_references: Vec::new(),
        common_proofs: Vec::new(),
        checks: Vec::new(),
        common_review_items: Vec::new(),
        domains: Vec::new(),
        cases: Vec::new(),
        errata: Vec::new(),
    }
}

/// Resolve a baseline into a [`ResolvedController`].
fn baseline(version: &TestCaseVersion, id: &str) -> ResolvedController {
    ResolvedController {
        controller: ControllerRef {
            id: id.to_string(),
            kind: ControllerKind::Baseline,
            label: None,
        },
        wasm: resolve_baseline(version, id).expect("baseline wasm"),
    }
}

fn decided(winner: Option<Team>, by: DecidedBy) -> Decided {
    Decided { winner, by }
}

#[test]
fn outcome_from_reads_each_side_of_a_decided_match() {
    let red_swept = decided(Some(Team::Red), DecidedBy::Sweep);
    assert_eq!(outcome_from(red_swept, Team::Red), AdversarialOutcome::Win);
    assert_eq!(
        outcome_from(red_swept, Team::Blue),
        AdversarialOutcome::Loss
    );

    // A level-score match broken by the efficiency tie-break is a plain win/loss —
    // the leaner side wins, the other loses, neither draws.
    let red_efficient = decided(Some(Team::Red), DecidedBy::Efficiency);
    assert_eq!(
        outcome_from(red_efficient, Team::Red),
        AdversarialOutcome::Win
    );
    assert_eq!(
        outcome_from(red_efficient, Team::Blue),
        AdversarialOutcome::Loss
    );

    // A genuine draw is level score *and* level fuel (reported as `Score`).
    let draw = decided(None, DecidedBy::Score);
    assert_eq!(outcome_from(draw, Team::Red), AdversarialOutcome::Draw);

    // A decided forfeit is the *losing* side forfeiting; the winner wins outright.
    let red_forfeited = decided(Some(Team::Blue), DecidedBy::Forfeit);
    assert_eq!(
        outcome_from(red_forfeited, Team::Red),
        AdversarialOutcome::Forfeit
    );
    assert_eq!(
        outcome_from(red_forfeited, Team::Blue),
        AdversarialOutcome::Win
    );

    // No winner on a forfeit means both forfeited.
    let both_forfeited = decided(None, DecidedBy::Forfeit);
    assert_eq!(
        outcome_from(both_forfeited, Team::Red),
        AdversarialOutcome::Forfeit
    );
}

#[test]
fn a_quick_match_between_baselines_produces_a_replay_and_summary() {
    let version = foray_version(1_500);
    let red = baseline(&version, "border-soldier");
    let blue = baseline(&version, "random");

    let outcome = run_quick_match(&version, &red, &blue).expect("quick match");
    assert!(outcome.replay.is_some(), "a played match yields a replay");
    let summary = outcome.summary;
    assert_eq!(summary.match_id, "border-soldier__vs__random");
    assert_eq!(summary.red_id, "border-soldier");
    assert_eq!(summary.blue_id, "random");
    // The replay's participants name the two controllers.
    let replay = outcome.replay.unwrap();
    assert_eq!(replay.participants.red, "border-soldier");
    assert_eq!(replay.participants.blue, "random");
}

#[test]
fn an_unloadable_controller_forfeits_with_no_replay() {
    let version = foray_version(1_500);
    let mut red = baseline(&version, "border-soldier");
    // Corrupt Red's module so it cannot load.
    red.wasm = b"not wasm".to_vec();
    let blue = baseline(&version, "random");

    let outcome = run_quick_match(&version, &red, &blue).expect("quick match");
    assert!(outcome.replay.is_none(), "no match ran, so no replay");
    let summary = outcome.summary;
    assert_eq!(summary.win_type, "forfeit");
    assert_eq!(summary.winner.as_deref(), Some("random"));
    assert_eq!(summary.outcome_for_red, AdversarialOutcome::Forfeit);
    assert!(summary.detail.is_some(), "the load failure is reported");
}

/// The controller identities of `participants`.
fn refs(participants: &[ResolvedController]) -> Vec<ControllerRef> {
    participants.iter().map(|p| p.controller.clone()).collect()
}

/// Play `pairings` of `participants` to the end, collecting every match.
fn play_all(
    version: &TestCaseVersion,
    participants: &[ResolvedController],
    pairings: &[TournamentPairing],
) -> Vec<TournamentMatch> {
    let mut played = Vec::new();
    run_tournament(version, participants, pairings, |played_match| {
        played.push(played_match);
        ControlFlow::Continue(())
    })
    .expect("tournament");
    played
}

#[test]
fn the_pairings_seat_the_lower_id_as_red_once_per_pair() {
    let field: Vec<ControllerRef> = ["random", "border-soldier", "greedy-raider"]
        .iter()
        .map(|id| ControllerRef {
            id: id.to_string(),
            kind: ControllerKind::Baseline,
            label: None,
        })
        .collect();
    let ids: Vec<String> = tournament_pairings(&field)
        .into_iter()
        .map(|pairing| pairing.match_id)
        .collect();
    assert_eq!(
        ids,
        vec![
            match_id("border-soldier", "greedy-raider"),
            match_id("border-soldier", "random"),
            match_id("greedy-raider", "random"),
        ]
    );
}

#[test]
fn a_tournament_plays_every_pairing_once_and_ranks_by_wins() {
    let version = foray_version(1_500);
    let participants = vec![
        baseline(&version, "border-soldier"),
        baseline(&version, "greedy-raider"),
        baseline(&version, "random"),
    ];
    let pairings = tournament_pairings(&refs(&participants));
    let played = play_all(&version, &participants, &pairings);

    // C(3,2) = 3 matches, each reported once, in pairing order.
    let ids: Vec<&str> = played.iter().map(|m| m.summary.match_id.as_str()).collect();
    let expected: Vec<&str> = pairings.iter().map(|p| p.match_id.as_str()).collect();
    assert_eq!(ids, expected);

    // Every match played produces a replay, and its summary points at the segment
    // the replay is stored under; without the key the board's Replay control
    // stays disabled.
    for played_match in &played {
        assert!(
            played_match.replay.is_some(),
            "every pair produces a replay"
        );
        assert_eq!(
            played_match.summary.replay_key.as_deref(),
            Some(played_match.summary.match_id.as_str()),
            "a played match keys its replay by the match id",
        );
    }

    let summaries: Vec<MatchSummary> = played.into_iter().map(|m| m.summary).collect();
    let standings = tournament_standings(&refs(&participants), &summaries);
    assert_eq!(standings.len(), 3);
    let ranks: Vec<u32> = standings.iter().map(|s| s.rank).collect();
    assert_eq!(ranks, vec![1, 2, 3]);
    for pair in standings.windows(2) {
        assert!(
            pair[0].wins >= pair[1].wins,
            "standings are sorted by wins, highest first"
        );
    }
    for standing in &standings {
        let id = &standing.participant_id;
        // A participant's wins are exactly the matches it was crowned the winner of
        // — and with the efficiency tie-break, a level-score match still has one.
        let won = summaries
            .iter()
            .filter(|m| m.winner.as_deref() == Some(id.as_str()))
            .count() as u32;
        assert_eq!(standing.wins, won, "wins == matches won");
        // Each controller meets the other two exactly once.
        assert_eq!(standing.wins + standing.losses + standing.draws, 2);
    }
}

#[test]
fn a_resumed_tournament_plays_only_the_pairings_it_is_given() {
    let version = foray_version(64);
    let participants = vec![
        baseline(&version, "border-soldier"),
        baseline(&version, "greedy-raider"),
        baseline(&version, "random"),
    ];
    let pairings = tournament_pairings(&refs(&participants));
    let played = play_all(&version, &participants, &pairings[1..]);
    let ids: Vec<&str> = played.iter().map(|m| m.summary.match_id.as_str()).collect();
    assert_eq!(
        ids,
        vec![pairings[1].match_id.as_str(), pairings[2].match_id.as_str()]
    );
}

#[test]
fn a_break_stops_the_tournament_before_the_next_pairing() {
    let version = foray_version(64);
    let participants = vec![
        baseline(&version, "border-soldier"),
        baseline(&version, "greedy-raider"),
        baseline(&version, "random"),
    ];
    let pairings = tournament_pairings(&refs(&participants));
    let mut reported = 0;
    run_tournament(&version, &participants, &pairings, |_| {
        reported += 1;
        ControlFlow::Break(())
    })
    .expect("tournament");
    assert_eq!(reported, 1);
}

#[test]
fn a_load_forfeit_reports_its_summary_without_a_replay() {
    let version = foray_version(64);
    let participants = vec![
        ResolvedController {
            controller: ControllerRef {
                id: "broken".to_string(),
                kind: ControllerKind::PushedRun,
                label: None,
            },
            wasm: b"\0not-wasm".to_vec(),
        },
        baseline(&version, "random"),
    ];
    let pairings = tournament_pairings(&refs(&participants));
    let played = play_all(&version, &participants, &pairings);
    assert_eq!(played.len(), 1);
    assert!(played[0].replay.is_none());
    assert_eq!(played[0].summary.replay_key, None);
    assert_eq!(played[0].summary.win_type, "forfeit");
}

#[test]
fn a_pairing_outside_the_field_is_a_case_error() {
    let version = foray_version(64);
    let participants = vec![baseline(&version, "random")];
    let pairings = vec![TournamentPairing {
        match_id: match_id("ghost", "random"),
        red_id: "ghost".to_string(),
        blue_id: "random".to_string(),
    }];
    let err = run_tournament(&version, &participants, &pairings, |_| {
        ControlFlow::Continue(())
    })
    .expect_err("an unknown participant");
    assert!(matches!(err, Error::Case(_)), "{err}");
}

#[test]
fn the_standings_count_a_draw_for_both_sides_and_break_ties_by_losses_then_id() {
    let field: Vec<ControllerRef> = ["a", "b", "c"]
        .iter()
        .map(|id| ControllerRef {
            id: id.to_string(),
            kind: ControllerKind::Baseline,
            label: None,
        })
        .collect();
    let summary = |red: &str, blue: &str, winner: Option<&str>| MatchSummary {
        match_id: match_id(red, blue),
        red_id: red.to_string(),
        blue_id: blue.to_string(),
        winner: winner.map(str::to_string),
        win_type: "time_limit".to_string(),
        outcome_for_red: AdversarialOutcome::Draw,
        red_score: 0,
        blue_score: 0,
        ticks: 1,
        red_kills: 0,
        blue_kills: 0,
        red_fuel: 0,
        blue_fuel: 0,
        replay_key: None,
        detail: None,
    };
    let matches = vec![
        summary("a", "b", None),
        summary("a", "c", Some("c")),
        summary("b", "c", Some("b")),
    ];
    let standings = tournament_standings(&field, &matches);
    let order: Vec<(&str, u32, u32, u32, u32)> = standings
        .iter()
        .map(|s| (s.participant_id.as_str(), s.wins, s.losses, s.draws, s.rank))
        .collect();
    // b and c each won one; b lost none (a draw), so it ranks above c.
    assert_eq!(
        order,
        vec![("b", 1, 0, 1, 1), ("c", 1, 1, 0, 2), ("a", 0, 1, 1, 3)]
    );
}

#[test]
fn every_arena_opponent_resolves_from_the_committed_case() {
    // The case must ship a `references/<id>.wasm` for every arena opponent,
    // including the hidden `fuel-probe` — otherwise auto-replay generation or an
    // arena match against it fails at run time.
    let version = foray_version(64);
    for id in ARENA_OPPONENT_IDS {
        let wasm = resolve_baseline(&version, id)
            .unwrap_or_else(|err| panic!("opponent `{id}` must resolve: {err}"));
        assert!(!wasm.is_empty(), "opponent `{id}` wasm is non-empty");
    }
}

#[test]
fn play_match_reports_a_controller_that_fails_to_load() {
    let version = foray_version(64);
    let good = resolve_baseline(&version, "random").expect("baseline");

    let played = play_match(&version, "red", b"\0not-wasm", "blue", &good).expect("played");
    assert!(
        matches!(
            played,
            Played::LoadFailed {
                team: Team::Red,
                ..
            }
        ),
        "{played:?}"
    );
    let played = play_match(&version, "red", &good, "blue", b"\0not-wasm").expect("played");
    assert!(
        matches!(
            played,
            Played::LoadFailed {
                team: Team::Blue,
                ..
            }
        ),
        "{played:?}"
    );
}

#[test]
fn a_case_missing_its_match_sections_names_each_one() {
    let mut version = foray_version(64);
    version.simulation = None;
    version.contract = None;
    let err = canonical_match_setup(&version, "red", "blue").expect_err("no setup");
    assert!(matches!(err, Error::Case(_)));
    assert_eq!(
        err.to_string(),
        "test case `foray@v1.0.0` declares no [contract], [simulation] for its adversarial match"
    );
}

#[test]
fn a_run_controller_resolves_from_the_run_output_dir() {
    let version = foray_version(64);
    let out = tempfile::tempdir().expect("tempdir");
    let module = out
        .path()
        .join("run-1/implementation/target/wasm32-unknown-unknown/release/controller.wasm");
    std::fs::create_dir_all(module.parent().expect("parent")).expect("dirs");
    std::fs::write(&module, b"wasm").expect("module");

    let bytes = resolve_run_controller(out.path(), "run-1", &version).expect("resolves");
    assert_eq!(bytes, b"wasm");
    let missing = resolve_run_controller(out.path(), "run-2", &version).expect_err("missing");
    assert!(matches!(missing, Error::Io(_)));
}
