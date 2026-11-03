# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from datetime import datetime, timedelta, timezone

NOW = datetime(2026, 10, 15, 12, tzinfo=timezone.utc)
REVISION = "47fc64adc9f74bc19a28aaf4b7226fa02a73a265"
PIPELINE_ID = 2948969220
PROJECT_ID = 123


def sample_report():
    six = "multi_device_sync::integration_six_device_"
    cases = {
        "test:release-rg3": [
            "orchestrator_default_ohttp::integration_ohttp_split_relay_config_routes_via_ohttp_relay"
        ],
        "test:release-rg4-rg5": [
            six + suffix for suffix in (
                "exchange_and_update_convergence", "single_exchange_convergence",
                "offline_catchup_converges_exact_values",
                "faulted_relay_delivery_converges_exact_values",
                "duplicate_ohttp_delivery_converges_exact_values",
                "concurrent_field_edits_converge",
                "bounded_clock_skew_converges_to_later_update",
                "replacement_and_revocation_preserve_active_convergence",
                "lost_primary_continuity_certification", "emergency_alert_certification",
            )
        ],
        "test:release-rg6-observability": [
            "ohttp_integration::integration_ohttp_relay_observations_exclude_update_content"
        ],
        "test:release-rg7": [
            "ohttp_source_address::application_relay_observes_the_ohttp_relay_never_the_end_user"
        ],
        "test:release-rg8": [
            "ohttp_fail_closed_matrix::hostile_bootstrap_responses_fail_closed",
            "ohttp_fail_closed_matrix::origin_boundary_probes_fail_closed",
            "action_family_oracles::hard_shred_after_grace_fanout_over_outer_hop_only",
            "action_family_oracles::panic_shred_with_contacts_sends_nothing_and_the_contact_keeps_me",
            "action_family_oracles::panic_shred_completes_local_erasure_without_network",
            "action_family_oracles::device_link_chain_makes_zero_requests_to_either_hop",
        ],
        "test:release-rg10": [
            six + suffix for suffix in (
                "personal_note_tombstone_converges_owner_only",
                "owner_private_state_converges", "visibility_override_removal_converges",
                "contact_override_clear_converges",
            )
        ],
        "test:release-rg15": [
            "longitudinal_continuity::integration_six_device_longitudinal_contact_continuity_certification",
            six + "replacement_and_revocation_preserve_active_convergence",
            six + "lost_primary_continuity_certification",
        ],
    }
    return {
        "schema_version": 1,
        "scope": "automated-privacy-multidevice",
        "pipeline": {
            "id": PIPELINE_ID, "project_id": PROJECT_ID, "sha": REVISION,
            "ref": "main", "status": "success",
            "created_at": "2026-10-15T01:25:47Z",
            "finished_at": "2026-10-15T02:00:00Z",
            "web_url": f"https://gitlab.com/vauchi/e2e/-/pipelines/{PIPELINE_ID}",
        },
        "sources": {
            "e2e": REVISION, "cli": "0" * 40, "relay": "1" * 40,
            "ohttp-relay": "2" * 40,
        },
        "lanes": [
            {
                "name": name, "job_id": index + 100, "pipeline_id": PIPELINE_ID,
                "sha": REVISION, "status": "success", "allow_failure": False,
                "finished_at": "2026-10-15T01:59:00Z",
                "cases": [{"name": case, "classname": "vauchi-e2e-tests::it",
                           "status": "success"} for case in selected],
            }
            for index, (name, selected) in enumerate(cases.items())
        ],
    }


def api_fixtures():
    report = sample_report()
    pipeline = report["pipeline"]
    jobs = [
        {
            "name": lane["name"], "id": lane["job_id"], "status": "success",
            "allow_failure": False, "finished_at": lane["finished_at"],
            "pipeline": pipeline,
        }
        for lane in report["lanes"]
    ]
    jobs.append({"name": "test:smoke", "id": 99, "status": "success",
                 "allow_failure": False, "pipeline": pipeline})
    suites = [
        {"name": lane["name"], "test_cases": lane["cases"], "suite_error": None,
         "total_count": len(lane["cases"]), "success_count": len(lane["cases"]),
         "failed_count": 0, "error_count": 0, "skipped_count": 0}
        for lane in report["lanes"]
    ]
    prefix = f"projects/vauchi%2Fe2e/pipelines/{PIPELINE_ID}"
    replies = {
        prefix: pipeline,
        prefix + "/jobs?per_page=100&page=1": jobs,
        prefix + "/test_report": {"test_suites": suites},
    }
    for component in ("cli", "relay", "ohttp"):
        source = "ohttp-relay" if component == "ohttp" else component
        replies[f"projects/vauchi%2Fe2e/jobs/99/artifacts/.smoke-bin/{component}.sha"] = (
            report["sources"][source] + "\n"
        )
    return replies


def fresh_report():
    report = sample_report()
    now = datetime.now(timezone.utc)
    report["pipeline"]["created_at"] = (now - timedelta(minutes=10)).isoformat()
    report["pipeline"]["finished_at"] = (now - timedelta(minutes=1)).isoformat()
    for lane in report["lanes"]:
        lane["finished_at"] = (now - timedelta(minutes=2)).isoformat()
    return report
