---
name: control-rig
display_name: Control Rig Authoring (FK / IK)
description: Author Control Rig (ControlRigBlueprint) assets via Python - hierarchy (bones/controls/nulls), control offsets that sit on bones, FK + Two-Bone-IK forward-solve graphs, FK/IK blend, master control hierarchy
vibeue_classes: []
unreal_classes:
  - ControlRigBlueprint
  - ControlRigBlueprintFactory
  - RigHierarchy
  - RigHierarchyController
  - RigVMController
  - RigControlSettings
  - RigUnit_TwoBoneIKSimple
keywords:
  - control rig
  - controlrig
  - CR_
  - rig
  - FK
  - IK
  - two bone ik
  - pole vector
  - forward solve
  - rig hierarchy
  - control offset
  - animator rig
  - sequencer rig
  - RigVM
---

# Control Rig Authoring Skill

> **Related Skills:** **skeleton** (read bone hierarchy), **animation-blueprint** (consume the rig), **blueprint-graphs** (general RigVM-like graph patterns).
>
> **Use this skill when:** building a Control Rig asset for a skeletal mesh from Python — an FK/IK animator rig to drive a character in Sequencer or an AnimBP.

There is **no stock "generate biped control rig" Python API**. You assemble the rig from primitives: hierarchy elements + a RigVM forward-solve graph. This skill is the verified recipe (UE 5.7), including the traps that crash or corrupt the editor.

## ⚠️ Critical traps (read first)

1. **`delete_asset` does NOT reliably delete a ControlRigBlueprint.** It returns `False` / hangs because the BP stays referenced in memory (RigVMController handles, open editor). To recreate at the same path you may instead get an auto-incremented `Name1` asset. **Fix:** rebuild the rig *in place* (see below), or close the editor and delete the `.uasset` from disk.
2. **A corrupt CR bricks the editor on load** (`FRigVMClient::PatchFunctionsOnLoad` in `PostLoad`). If a node-add crashed mid-write, double-clicking the asset crashes the editor. **Fix:** with the editor closed, delete the bad `.uasset` from disk.
3. **`RigUnit_TwoBoneIKSimplePerItem` (the array variant) crashed the editor** (access violation) when added headless. **Use `RigUnit_TwoBoneIKSimple`** (name-based `BoneA/BoneB/EffectorBone`) instead.
4. **A poisoned interpreter cascades crashes.** After any timeout/crash, further `add_unit_node` calls may crash on memory the prior crash corrupted. **Restart the editor for a clean session** before authoring graph nodes.
5. **Do NOT read control global transforms mid-build to position children.** `get_global_transform(control)` includes the control's *value* (pose), not just offset, and mid-build offsets stack. Use the **bone-local offset recipe** below — pure static bone data, reload-stable.

## Create the asset + import bones

```python
import unreal
MESH = unreal.load_asset("/Plugin/SKM_Character")
bp = unreal.ControlRigBlueprintFactory().create_new_control_rig_asset("/Plugin/CR_Character")
# NOTE: factory auto-persists to disk immediately, and the fresh BP ALREADY has a
# Forward Solve entry node (RigUnit_BeginExecution) - do not add another or you get
# "Event Forwards Solve already exists".
h  = bp.hierarchy
hc = h.get_controller()
hc.import_bones_from_skeletal_mesh(MESH, unreal.Name(""), False, True)  # (mesh, namespace, replace, select)
bp.set_editor_property("preview_skeletal_mesh", MESH)
```

## Controls that sit exactly on bones (THE recipe)

`set_control_offset_transform(key, t, initial, affect_children)` takes `t` in **parent space (local)**. The reload-stable way to place an FK control chain that mirrors the bone chain:

- **Create controls parent-first** (parent control = the parent *bone's* control).
- For each FK control set `offset = bone LOCAL transform` (`h.get_local_transform(bone_key, True)`).
- For a **root-parented** control (parent is identity), `offset = bone GLOBAL transform`.
- Controls must be **fresh** (offset set once). Re-setting offsets on already-positioned, value-dirty controls accumulates error.

```python
def ck(n): return unreal.RigElementKey(type=unreal.RigElementType.CONTROL, name=n)
def bk(n): return unreal.RigElementKey(type=unreal.RigElementType.BONE, name=n)

def settings(ctype, shape, color, vis=True):
    s = unreal.RigControlSettings(); s.control_type = ctype
    s.shape_visible = vis; s.shape_name = shape; s.shape_color = color
    return s

ET = unreal.RigControlType.EULER_TRANSFORM
tv = unreal.RigHierarchy.make_control_value_from_euler_transform(unreal.EulerTransform())

# root + FK chain (bones already in parent-first order from get_all_keys)
hc.add_control(unreal.Name("root_ctrl"), unreal.RigElementKey(), settings(ET,"Circle",unreal.LinearColor(0,1,1,1)), tv)
for bn in controlled_bones:                       # parent-first
    parent = "root_ctrl" if bn == root_bone else (parent_bone[bn] + "_ctrl")
    hc.add_control(unreal.Name(bn+"_ctrl"), ck(parent), settings(ET,"Box_Thick",unreal.LinearColor(1,1,0,1)), tv)
    h.set_control_offset_transform(ck(bn+"_ctrl"), h.get_local_transform(bk(bn), True), True, False)
```

Verify with `get_global_control_offset_transform(ctrl, True).translation` ≈ `get_global_transform(bone, True).translation` — and **re-check after `load_asset` reload**, because that is where the fragile approaches silently revert.

`make_control_value_from_float(0.0)` + `RigControlType.FLOAT` makes a scalar control (good for FK/IK switches). `h.set_control_shape_transform(key, t_with_scale, True)` scales gizmos.

## FK forward solve (per bone)

For each controlled bone, drive the bone from its control in **global space**, chaining the execute pins **parent-first** (`bPropagateToChildren=True` so uncontrolled tips follow):

```python
model = bp.get_controller_by_name("RigVMModel")
def ss(n):
    for s in model.get_registered_unit_structs():
        if s.get_name()==n: return s
GET, SET = ss("RigUnit_GetTransform"), ss("RigUnit_SetTransform")
prev = "<ForwardSolveNode>.ExecutePin"            # the pre-existing BeginExecution node's exec out
for bn in controlled_bones:
    model.add_unit_node(GET, "Execute", unreal.Vector2D(0,y),   f"GetT_{bn}")
    model.add_unit_node(SET, "Execute", unreal.Vector2D(350,y), f"SetT_{bn}")
    model.set_pin_default_value(f"GetT_{bn}.Item", f'(Type=Control,Name="{bn}_ctrl")')
    model.set_pin_default_value(f"GetT_{bn}.Space", "GlobalSpace")
    model.set_pin_default_value(f"SetT_{bn}.Item", f'(Type=Bone,Name="{bn}")')
    model.set_pin_default_value(f"SetT_{bn}.Space", "GlobalSpace")
    model.set_pin_default_value(f"SetT_{bn}.bPropagateToChildren", "True")
    model.add_link(f"GetT_{bn}.Transform", f"SetT_{bn}.Value")
    model.add_link(prev, f"SetT_{bn}.ExecutePin")
    prev = f"SetT_{bn}.ExecutePin"
```

Element-key pins are set with a struct string: `(Type=Control,Name="x")` / `(Type=Bone,Name="x")`. Enum pins by name string: `"GlobalSpace"`, `"Location"`.

## Two-Bone IK + FK/IK blend

Use **`RigUnit_TwoBoneIKSimple`** (NOT the PerItem variant). Run it **after** the FK chain so `Weight` blends FK→IK (0 = FK, 1 = IK). Effector + pole come from controls; the switch is a float control read by `RigUnit_GetControlFloat` (output pin `FloatValue`).

```python
IK = ss("RigUnit_TwoBoneIKSimple")
ML = unreal.MathLibrary
# PrimaryAxis = bone-local direction A->B (so the solver aims the bone correctly); pole drives bend with SecondaryAxisWeight=0
pax = ML.normal(ML.inverse_transform_location(bg(boneA), bg(boneB).translation))
model.set_pin_default_value("IK_x.BoneA", boneA)
model.set_pin_default_value("IK_x.BoneB", boneB)
model.set_pin_default_value("IK_x.EffectorBone", effBone)
model.set_pin_default_value("IK_x.PrimaryAxis", f"(X={pax.x},Y={pax.y},Z={pax.z})")
model.set_pin_default_value("IK_x.SecondaryAxisWeight", "0.0")
model.set_pin_default_value("IK_x.PoleVectorKind", "Location")
model.add_link("GetEff_x.Transform", "IK_x.Effector")
model.add_link("GetPole_x.Transform.Translation", "IK_x.PoleVector")   # sub-pin (Transform.Translation) -> FVector link WORKS
model.add_link("GetSw_x.FloatValue", "IK_x.Weight")
model.add_link(prev_exec, "IK_x.ExecutePin")
```

Place a pole control at: `pole = midJoint + normalize(midJoint - midpoint(root,effector)) * (limbLength*0.5)` (elbow points back, knee points forward).

## In-place rebuild (when offsets/controls are wrong but the graph is fine)

The RigVM graph references controls by **name string** (in pin defaults), not by object. So you can fix a polluted control hierarchy without touching the graph:

```python
for k in [k for k in h.get_all_keys() if k.type==unreal.RigElementType.CONTROL]:
    hc.remove_element(k)
# ... re-add all controls with the SAME names + correct offsets ...
```
The graph's `GetT_*` / `GetEff_*` pins reconnect logically to the re-created same-named controls. This sidesteps the un-deletable-asset trap entirely.

## Master control hierarchy (animator ergonomics)

Mirror production rigs (e.g. Tatools): `global_ctrl → root_ctrl → body_ctrl → hips → spine…`, with IK/pole/switch controls parented under `global_ctrl`. Master controls **drive nothing directly** — they are parents whose motion propagates into the FK controls, and because the forward solve reads each FK control's *global*, moving `global_ctrl`/`body_ctrl` moves the whole character for free (no extra graph nodes). `body_ctrl` offset = hips global; `hips_ctrl` (parented under `body_ctrl`) offset = identity.

## Verify

`unreal.BlueprintEditorLibrary.compile_blueprint(bp)` then `unreal.EditorAssetLibrary.save_asset(path, True)`. Compile success + all controls-on-bones (after reload) + a fully chained execute path (BeginExecution → every SetT → every IK) is the static gate.

### Runtime verification (safe — executing a compiled rig does NOT crash)

Unlike *authoring* nodes (which can crash a poisoned interpreter), *executing* a clean compiled rig is safe. Instantiate it, drive a control, run the solve, read the bone — definitive proof:

```python
cr = bp.create_control_rig()
cr.request_init()
hier = cr.get_hierarchy()                       # the instance's own DynamicHierarchy
cr.execute("Construction Event")
cr.execute("Forwards Solve")                     # baseline pose
base = hier.get_global_transform(bk("Hips")).translation

# move a control on the INSTANCE hierarchy, re-solve, read the driven bone
et = unreal.EulerTransform(); et.location = unreal.Vector(0,0,50)
hier.set_control_value(ck("body_ctrl"),
    unreal.RigHierarchy.make_control_value_from_euler_transform(et),
    unreal.RigControlValueType.CURRENT)
cr.execute("Forwards Solve")
moved = hier.get_global_transform(bk("Hips")).translation   # Hips.z should be base.z + 50
```

Float switches: `make_control_value_from_float(1.0)`. To prove FK/IK blend: with the switch at 0, moving the IK effector control must NOT move the bone; at 1, it must. (Verified on `CR_KimodoSOMARig`: `body_ctrl +Z50` → Hips & Head both Δ+50; `arm_l_fkik` 0→1 with a raised `hand_l_ik_ctrl` → LeftHand Δz 0 → +27.9.)
