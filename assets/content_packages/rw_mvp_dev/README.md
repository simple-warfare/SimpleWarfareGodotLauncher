# RW MVP Development Package

This package is a clean Simple Warfare development target derived from local Rusted Warfare reference data.

It is not a raw converter output. The package intentionally reshapes the source data into a compact, engine-oriented schema so the Rust content loader can evolve toward this structure.

## Scope

- One playable faction.
- One resource.
- Six unit definitions: builder, factory, extractor, turret, tank, artillery, helicopter.
- Shared weapon/projectile definitions.
- One small two-team test map.
- Self-contained selected image assets copied from the local reference tree.

## Design Rules

- No raw legacy INI is embedded.
- Every gameplay definition keeps a source trace to the original reference file and key values.
- Repeated combat data lives in `weapons/common.toml` and units reference weapon ids.
- Units are grouped by domain instead of split into many tiny files.
- Map terrain uses fixed-width row strings for compact storage and cache-friendly decoding.

## Parser Target

This package is a schema target. Existing content code may not parse it yet.

The intended loader pipeline is:

1. Read `manifest.toml`.
2. Resolve `indexes/*.toml`.
3. Load resources, factions, weapons, units, maps and assets.
4. Normalize package-local ids.
5. Validate references and produce runtime spawn plans.
