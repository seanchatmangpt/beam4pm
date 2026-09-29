---
id: g3-port-bridge-pack
dcterms:title: "pack facts that render JSON-lines port-bridge GenServer clients (generalize P8's hand-written BeamPM.AutofdeBridge)"
standing: BLOCKED
---
Worktree: ~/ggen-marketplace-wt/g3 (branch pack/port-bridge). Proof scratch:
/Users/sac/beam4pm-worktrees/wt-g3-proof. Read _G-CONTEXT.md.
Author bpm:PortBridge vocabulary (bridgeCommand, ops w/ request/reply
shapes, framing, restart policy, timeouts) + template rendering a
GenServer-wrapped Port client per P8's law (timeout, FIFO waiters,
:bridge_down, restart). PROOF: (1) render an instance against a tiny echo
bridge fixture shipped in the pack's qualification/ and run it green;
(2) diff the rendered shape vs P8's hand-written file
(beam4pm-worktrees/wt-p8/lib/beam4pm_autofde_bridge.ex) and state coverage
honestly; (3) gate refuses an op with no reply shape.
Pack version bump + dated description.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-19T00:30:00Z | ALIVE | marketplace pack/port-bridge @ 3d5009a70 | bpm:PortBridge family + client/test templates + gate 100 + echo fixture (1,209 法面 lines). Proof: 524/524 delivered lines rendered (0 hand); 8/0 ×4 vs real fixture bridge; kill -9 recovery + timeout poisoning witnessed; gate refuses op-without-reply-shape by name; gate STRENGTHENED after falsifier exposed consumer-minted-vocabulary hole. Coverage vs P8: 82% (18% = one-shot CLI family → G1's class, failed edge recorded). FINDING: rendering caught the hand original's latent request/2 default-misbinding — permanent guards added. Remaining: consumer cutover retires BeamPM.AutofdeBridge | cutover at integration |
