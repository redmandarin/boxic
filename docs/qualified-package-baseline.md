# Qualified package source baseline

Reconciled 2026-10-26 before implementation. No Wedge dependency files changed.

## Git provenance

`git ls-remote --heads --tags` against `koenusz/boxic` and
`redmandarin/boxic` found both main branches at
`0eaeb0c3e16fa0e85533f063a0198ad7daf71683`. Upstream additionally exposes
`agent/boxic-dmn-0.2.0` at `8c1706fadd89aa328d56c39e86edd49708876479`.
The only upstream tags are `boxic_dmn-v0.1.0` and `boxic_feel-v0.1.0`,
both peeling to `e755e905c620a4b4cc53f6c77424716446e62cbb`.
The fork exposes only main and no release tags.

The newer upstream branch descends directly from main through six commits:
`8d6a4b4` (writer/authoring), `3ae234b` (CI), `cc8504e` (release checks),
`2382287` (TCK execution), `45d6001` (CI), `8c1706f` (DMN 1.5).
The work branch fast-forwards to the full upstream history; it does not
reconstruct source from Hex or rewrite upstream commits.

## Content verification

Downloaded the original tarballs from `https://repo.hex.pm/tarballs/` and
compared every unpacked package file against `git archive 8c1706f`.
The SHA-256 of each tarball agrees with its Hex release API checksum:

| Package | Release | Tarball SHA-256 |
| --- | --- | --- |
| boxic_dmn | 0.3.0 | edfda30ff21010693baa6dd3e067d0b9ec95b6f480efe10d26238a46953b4322 |
| boxic_feel | 0.2.0 | 05bc8309aa62b2f8ad1c0b3b32055cade0a636796ce9fd0eacd9dac326fc3683 |

[The file manifest](qualified-package-baseline.json) records all package file
hashes, identical runtime/schema counts and source-only runtime files.
**Every `lib/` and `priv/` file matches byte-for-byte in both directions.**
Only `mix.exs`, `README.md` and `CHANGELOG.md` differ in either package:

- DMN source declares 0.2.0 and FEEL `~> 0.1.0`; Hex declares 0.3.0 and
  FEEL `~> 0.2.0`. FEEL source declares 0.1.0; Hex declares 0.2.0.
- Both Hex mix files remove the four umbrella build/config/deps/lock paths.
  DMN's Hex mix file also removes `in_umbrella: true` from the sibling branch
  of its dependency selection. Runtime extra applications are identical.
- README install examples use the released versions. FEEL's Hex README
  updates its TCK pin from `0dbcaf9b...` to `a162739d...`.
- Changelogs add July 24 release headings and conformance-result text; DMN
  also labels the sole DMN 1.5 executable profile as breaking.

Thus `8c1706f` is an established **runtime/schema source baseline** for the
qualified packages, not an identical release tree or a verified release tag.
Tests/build tooling are available in Git but absent from Hex and cannot be
authenticated as release inputs from the published packages. Recommended
upstream housekeeping: record release tags and reconcile version/dependency
metadata in a separate release change. This task does not invent tags or bump
package versions.

## Dependencies and qualification reference

Both releases require Elixir `~> 1.20.0`. FEEL requires Decimal `~> 3.1` and
tz `~> 0.28.2`. The Git lock pins Decimal 3.1.1 and tz 0.28.2; Wedge's
qualification used Decimal 3.2.0 and tz 0.28.4, with Elixir 1.20.4 / OTP
28.5.0.8. Dependency-sensitive qualification should cover both Decimal pins.
`mix deps.get` reports an advisory for the existing locked Decimal 3.1.1
(`EEF-CVE-2026-97853`, unbounded allocation in `round/3`); upgrading dependencies
is outside this focused change. Wedge's existing 3.2.0 pin is untouched.

References read in the sibling Wedge checkout (`projects/yv`):
`tasks/decision_models/02_contracts/executor_report.md`,
`alternatives_report.md`, qualification fixtures, helper and reproduction
script. Those reports establish the malformed-FEEL preflight gap and preserve
separate arithmetic/containment findings; no application work is included.

Sources: [DMN release metadata](https://hex.pm/api/packages/boxic_dmn/releases/0.3.0),
[FEEL release metadata](https://hex.pm/api/packages/boxic_feel/releases/0.2.0),
[upstream source](https://github.com/koenusz/boxic/commit/8c1706fadd89aa328d56c39e86edd49708876479).
