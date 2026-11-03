# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Required automated scenarios; native and operator acceptance is separate."""

SIX_DEVICE = "multi_device_sync::integration_six_device_"
LIFECYCLE = {
    SIX_DEVICE + "replacement_and_revocation_preserve_active_convergence",
    SIX_DEVICE + "lost_primary_continuity_certification",
}
REQUIRED_CASES = {
    "test:release-rg3": {
        "orchestrator_default_ohttp::integration_ohttp_split_relay_config_routes_via_ohttp_relay"
    },
    "test:release-rg4-rg5": LIFECYCLE | {
        SIX_DEVICE + suffix for suffix in (
            "exchange_and_update_convergence", "single_exchange_convergence",
            "offline_catchup_converges_exact_values",
            "faulted_relay_delivery_converges_exact_values",
            "duplicate_ohttp_delivery_converges_exact_values",
            "concurrent_field_edits_converge",
            "bounded_clock_skew_converges_to_later_update", "emergency_alert_certification",
        )
    },
    "test:release-rg6-observability": {
        "ohttp_integration::integration_ohttp_relay_observations_exclude_update_content"
    },
    "test:release-rg7": {
        "ohttp_source_address::application_relay_observes_the_ohttp_relay_never_the_end_user"
    },
    "test:release-rg8": {
        "ohttp_fail_closed_matrix::hostile_bootstrap_responses_fail_closed",
        "ohttp_fail_closed_matrix::origin_boundary_probes_fail_closed",
        "action_family_oracles::hard_shred_after_grace_fanout_over_outer_hop_only",
        "action_family_oracles::panic_shred_with_contacts_sends_nothing_and_the_contact_keeps_me",
        "action_family_oracles::panic_shred_completes_local_erasure_without_network",
        "action_family_oracles::device_link_chain_makes_zero_requests_to_either_hop",
    },
    "test:release-rg10": {
        SIX_DEVICE + suffix for suffix in (
            "personal_note_tombstone_converges_owner_only", "owner_private_state_converges",
            "visibility_override_removal_converges", "contact_override_clear_converges",
        )
    },
    "test:release-rg15": LIFECYCLE | {
        "longitudinal_continuity::integration_six_device_longitudinal_contact_continuity_certification"
    },
}
