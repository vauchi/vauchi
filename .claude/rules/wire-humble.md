## CoreUI Wire Humble (MANDATORY)

Adopted 2026-05-03 across `vauchi-core` 0.41.0 (see Tier 0 of
`2026-05-03-coreui-wire-humble-types` problem record + ADR-044).
Enforced at runtime by
`core/vauchi-app/tests/it/wire_humble_keys_tests.rs` — the 8-key
deny-list regression test fails if a retired domain-shaped JSON
key reappears in any `Component` variant's serialized output.

### The invariant

CoreUI wire types — anything serialized over CABI / UniFFI / JSON
to a frontend renderer — **carry only presentation**:

- Type names are UI-shaped: `Item`, `Field`, `PreviewVariant`,
  `Component::List`, `Component::Preview`. **Never** `ContactItem`,
  `FieldDisplay`, `GroupCardView`, `Component::ContactList`,
  `Component::CardPreview`.
- Field names are UI-shaped: `items`, `variants`, `variant_id`,
  `selected_variant`. **Never** `contacts`, `group_views`,
  `group_name`, `selected_group`.
- Engine-input data (search indices, filter predicates, etc.)
  **never** crosses the serde boundary. Move it to an engine-side
  sidecar struct (e.g. `ContactListEngine` keeps
  `Vec<IndexedItem>` internally; emits `Vec<Item>` on the wire).

### Why

A renderer that knows what kind of thing it is rendering can
re-domain itself over time (ADR-021, ADR-043). Domain-shaped wire
types ossify the wrong abstraction even when the renderer code
itself is humble — every consumer ends up with `for contact in
contacts: ContactItem`, and the rename of binding-only
identifiers (`for item in items: ContactItem`) silently re-domains
under the next refactor pressure. Pure binding renames are
half-measures; the wire shape is the durable seam.

### Engine-side typing is fine — Rust-only

`Item<T>` patterns, parallel engine types like
`DecoyContactItem`, domain-named engine structs — all welcome on
the Rust side. The discipline is at the **serde boundary**, not
inside the engine. Engines are domain-aware by design (ADR-021);
their types are too.

### Adding a new Component variant

1. **Field names**: pick UI-shaped names. If you need a
   purely-presentational hint (icon, empty-text key,
   "+ Add" label key), use a closed-enum field like
   `kind: SomeKind` whose values are looked up against a
   *static i18n key / icon-name table* — never a domain branch.
   The slippery slope here is `ListKind`-style enums driving
   *behavioral* logic. Don't.
2. **Engine input**: keep it in the engine, not on the wire.
   The wire shape ships only what the renderer reads.
3. **Run the regression test**:
   `just test-name wire_humble_keys core` — green confirms no
   retired domain-shaped key reappeared. (The test is curated;
   if you add a new variant, append a sample to
   `all_components()` so its JSON is walked.)

### Adding a new wire field

Wire field names go through `serde` with default snake_case.
Pick from the UI-shaped vocabulary: `id`, `label`, `value`,
`title`, `subtitle`, `detail`, `items`, `actions`, `variant_id`,
`selected_variant`, `kind`, `style`, `visibility`, `searchable`,
`a11y`, `placeholder`, `validation_error`. Domain words
(`contact`, `card`, `group_*`, `searchable_fields`, `field_type`'s
domain values, etc.) are tripwires — the regression test catches
them.

### Counter-intuitive: stay-domain-named exemptions

Some wire constructs are *data* about a domain feature, not a
renderer-leaks-domain. Keep them named for what they are:

- `UiFieldVisibility::Groups(Vec<String>)` — the variant data
  *is* group memberships. The renderer routes on the
  discriminant; it doesn't read "groups". Keep.
- `Component::FieldList { available_groups: Vec<String> }` —
  same: data shape, no domain branching by the renderer. Keep.

The deny-list in `wire_humble_keys_tests.rs` is the
ground-truth for what's been retired. When the test fires, do
not "fix" it by widening the deny-list. Pick a UI-shaped name
for the new key. The deny-list is a record of names already
retired — adding to it is fine when retiring more, never to
silence a regression.

### Reversibility

Each rename in Tier 0 used `serde` defaults (no aliases shipped),
so wire JSON now requires the new keys. Out-of-tree consumers
do not exist; in-tree consumers (linux-gtk, linux-qt, windows,
TUI, iOS, macOS, android) update via Tier 1 MRs paired with the
core release. Reverting requires re-renaming both Rust types
and frontend renderers — not free, but no protocol or storage
state depends on these names.

Full Tier 0 history + design rationale:
`_private/docs/designs/2026-05-03-coreui-wire-humble-types-design.md`,
`_private/docs/decisions/adr-044-coreui-wire-humble-types.md`,
`_private/docs/problems/2026-05-03-coreui-wire-humble-types/`.
