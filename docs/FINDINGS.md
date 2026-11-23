# Meth Lab HUD: game data findings

What the mod relies on, learned from PAYDAY 3's game files, the MoolahProject
headers, and in-game logs (UE4SS.log, `[MethCook]` lines) in November 2026.
The mod's folder and log tag are still `MethCook`, its working name.

## Cooking station (both heists)
- Class: `BP_MethCookingStation_C`, native parent `ASBZCookingStation` (inherits `ASBZMultiBagGenerator`).
  The BP lives at `/Game/DLCs/00004-DLCREMA/Prototype/Maps/Villa/Blueprints/BP_MethCookingStation`.
- `CurrentState` (replicated) is an `ESBZCookingState`:
  0 Inactive, 1 WaitingForIngredients, 2 Cooking, 3 UnderCooked (raw), 4 Cooked (perfect), 5 OverCooked, 6 Sabotaged, 7 Destroyed.
- Timings seen: Cooking ~3 s, then raw ~10 s, then perfect, then overcooked.
  The intervals are random per difficulty (`CookingDurationArray[4]`), and a Demolitionist skill extends the perfect window.
- Hookable BP events:
  - `BP_OnStateChanged(old, new, cosmetics)`
  - `BP_OnIngredientAdded(slot 1..3)`
  - `BP_OnStaticOrderGenerated(order)`: Party Powder only, fires at map load
  - `ReceiveBeginPlay`
- Pour slots: 1 = MU, 2 = CS, 3 = HCL (same in Party Powder and Cook Off). The station's `Ingredient1..3` meshes are generic (SlowCookers / LiquidTank / LiquidMeth) and don't identify the slot.
- "Processing" after a pour: all three `IngredientInteractableArray[i].bInteractionEnabled` go false right after the pour and true again when the next pour is allowed (15–29 s seen). No state change in between.
- Bags: `NumberOfBags` is the configured total and `BagHandleArray` holds the bags still to come. Party Powder: 4 → 3 per bag. Cook Off: 19 total but 1 handle (not a "bags left" counter), so the mod shows ∞.
- Sabotage (generator cut): state goes Waiting → Sabotaged → Waiting. Pours made before it are kept.
- Wrong ingredient = explosion (state 7, Destroyed).
- `StaticFindObject("<BP class>:<function>")` returns nothing for BP functions in this UE4SS build. Check the class instead and just try `RegisterHook`.

## Party Powder (internal name Bust)
- The recipe is static and comes at map load via `BP_OnStaticOrderGenerated`. The order lists 0-based pour slots: `{2,0,1}` = slot 3 → 1 → 2 = HCL → MU → CS (confirmed in-game).
- Recipe displays are the station's `recipeActors`: `BP_MethMeshCode_01` (ingredient images, no interaction or event).
  - Positions vary per run; one copy sits at (0 0 0), unused.
  - Readable side faces −forward: a straight-on read gave forward·(cam−display) = −1.0, and a side-window glimpse gave +0.24.
- `WasRecentlyRendered` alone passes through walls. A line trace (`KismetSystemLibrary.LineTraceSingle`, Visibility channel) is needed.
- Ingredient pickups: `BP_Meth_CausticSoda_C` / `_HydrogenChloride_C` / `_MuriaticAcid_C`, 6 of each.
  - Ghost copies sit at (0 0 0) and disappear within about 12 s.
  - A taken pickup has `bHidden = true`.
- Outlines (`SBZOutline`) couldn't be forced from Lua: neither ActiveReplicated + OnRep nor a DefaultAsset swap showed anything.

## Cook Off (DLC 00242-COOKIE)
- No static recipe. The server picks each ingredient the moment the lab is ready for it.
  - Level script `/Game/DLCs/00242-COOKIE/Maps/Sublevels/Gameplay_Cookie/G_Cookie_Scripting.G_Cookie_Scripting_C` binds the stations' host-only `OnRequiredIngredientChanged` to
    `BndEvt__G_Villa_Scripting_BP_MethCookingStation{_2 #55, 2 #56, 3_6 #57}_..._SBZCookingStationIngredientDelegate__DelegateSignature(NewIngredientIndex)`.
  - `NewIngredientIndex` is the pour slot (1 MU, 2 CS, 3 HCL).
  - **Host only.** No synced signal for clients was found: outlines only change on focus, and the pour points all turn on together.
- Script variables: `IngredientRequestActive`, `LastUsedIngredient`, `UsedIngredients`, `CookingIsInfinite`, `MaxBagsofMethCooked`, `FirstRequestIngredientVO`, `IngredientReminder`.
- The lab is Inactive until the first ingredient request.

### Shade's dialogue (what the player hears)
- Readable without hooks: the `SBZDialogManager` component on the GameState (`BP_HeistGameState_C...SBZDialogManager`).
  - Its `ActiveDialogs` TMap keys are dialog assets named `sha_rmk02_GG` (per group; the variant is picked inside).
  - How long a key stays in the map does NOT match playback (an entry left after 0.8 s while its full subtitle showed). Subtitles appear about 0.4 s after the entry.
- Subtitle text on screen: `WBP_UI_Widget_Subtitles_C.Text_SubtitleText:GetText()`.
- Groups (dev descriptions from ST_Subtitles `_01` entries):
  - 22 "Operator Preparing Next Step": "Checking the notes..."
  - 16/17/18 "Cooking Instructions": MU / CS / HCL
  - 19/20/21 "One-Off": MU / CS / HCL (short calls)
  - 29 "Operator Uncertain": "...I'm 68% sure", "...I think". NOT a confirmation, just flavour; it plays after about half of all calls.
  - 24 "Cooking - Encouragement": "Go for it."
  - 25 "Cooking - Warning": "Hold up!", "Wait a second...", "Stop! That was wrong.". This is the only fake-out signal.
  - 26/27/28 "Operator Corrects Mistake": MU / CS / HCL
  - 23 "Operator Admits Mistake": a quip, can follow a warning
  - 15 "Cook Going Well": plays after each pour
  - 14 power cut, 37 power reminder, 30/49 batch done, 51–53 lab blown up, 38–48 cop and sniper warnings, 50 assault over
- **Fake-out timing (4 samples):** the warning comes **1.9–2.05 s after the call**, which is almost certainly a fixed delay in the script.
  - The correction follows 3–11 s later, and other lines can cut in first.
  - A correction can be a normal instruction line (e.g. "Connect the tank of hydrogen chloride."), not only 26–28.
- **Sample statistics (one evening, ~60 calls):** instruction lines (16–18) were correct 51/51; one-off lines (19–21) were fake 4/10.
  - All fake calls were one-offs, and none had the 22 intro.
  - The mod uses this split: instruction lines count as final at once, one-offs show "?" for 5 s, and a warning overrides both.
- The full label rules are in `onDialog` and `cookOffLabel` in `MethCook/Scripts/main.lua`.

## Other game findings
- Doors: `ASBZGate:SetState(0)` opens any gate. `ESBZGateState`: 0 OpenForward, 1 OpenBackward, 2 SlammedClose, 3 Closed, 4 Locked, 5 Sealed, 6 Barricaded, 7–8 Breached, 9–10 SlammedOpen.
- Removing guards (`K2_DestroyActor` on `SBZAICharacter`) triggered an alarm; the cause wasn't isolated. Removed classes were `CH_Cop_Street_C` ×13 and `CH_SecurityGuard_C` ×1.

## UE4SS crash rules (this build; pcall does not catch these)
- Never call a UFunction with a delegate parameter (`AkGameplayStatics.PostEvent` crashed in push_delegateproperty). Use `PostEventAtLocation` at the camera for a non-spatial sound.
- Never read delegate properties through `obj[name]`.
- Keep `FindAllOf` rare; 8 classes at 4 Hz made the game stutter.
- All Lua must run on the game thread (`LoopInGameThreadAfterFrames`). Poll keys with `WasInputKeyJustPressed`.
- Some SS_ sprites never load standalone (WpFix, skill-line icons, VIPInvalid, the explosives pickup) and draw as solid tinted squares.
- UE4SS hot reload (Ctrl+R) can crash Lua mods, even in the main menu. Restart the game after changing a mod.
- `StaticFindObject` on an object that isn't loaded costs about 5 ms in this build (a loaded one about 0.02 ms). Only look things up on maps that can have them, and keep what you find.
