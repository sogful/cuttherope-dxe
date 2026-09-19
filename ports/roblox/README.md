# Roblox port

This is a source-faithful Luau port of Cut the Rope DX. It is not compiled from
the C# projects.

- `src` contains authored runtime modules grouped by Roblox service.
- `tests` contains Roblox checks and generated golden data.
- `generated` contains port assets and C# reference traces.
- `../../tools/roblox` contains generators and audit tools.

Run generators from the repository root. They read the canonical `src` and
`content` trees directly; no duplicated DX checkout is required.
