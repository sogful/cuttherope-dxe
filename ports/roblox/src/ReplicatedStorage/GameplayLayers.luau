-- GameScene.Draw.cs draw passes, not arbitrary per-object priorities.
-- ScreenGui uses Sibling: assign these to the world-root holders, not just art.
return table.freeze({
	Pollen=4, GravitySwitch=5, MouseHole=6, Support=10, Target=11, Disc=15, Conveyor=18,
	Mouse=47,
	BubbleShadow=20, Bubble=21, Pump=30, Hazard=40, Bouncer=45, Hat=50,
	SteamBack=52, Lantern=53, SteamFront=85,
	HookBack=60, RopeOutline=61, Rope=62, HookHighlight=63, HookFront=64,
	WheelBase=60, WheelArm=65, Bee=66,
	StarRing=70, Star=71, StarBurst=72, Candy=80,
	AttachedBubble=81, Spider=90, Effect=100,
})
