# URP Tech Art Sandbox

A Unity **2021.3 LTS + Universal Render Pipeline 12.1.15** playground for real-time rendering
techniques: GPU-driven grass, two independent fur pipelines, an FFT ocean, a procedurally
layered stylized skybox, and a full anime / NPR character shading set — plus the authoring
tools that make them usable in an editor.

![Unity](https://img.shields.io/badge/Unity-2021.3.45f1-000000?logo=unity&logoColor=white)
![URP](https://img.shields.io/badge/URP-12.1.15-4B8BBE)
![License](https://img.shields.io/badge/license-MIT-blue)

> **中文摘要**
>
> 这是一个 Unity 2021.3 + URP 12.1.15 的实时渲染技术试验场，包含五套独立的技术演示：
> GPU 驱动的草地（compute 剔除 + `DrawMeshInstancedIndirect` + 交互推力场）、
> 两种毛发方案（壳层 / 屏幕空间后处理）、FFT 海洋水面（含平面反射与抖动混合）、
> 分层叠加的风格化天空球，以及一整套三渲二 / NPR 角色着色器（Ramp 阴影、双通道法线、
> Stencil 描边、MatCap、头发高光）。
>
> 除了着色器，工程里还带一整套编辑器工具链：草叶网格生成、草场烘焙、道路/分布绘制、
> 噪声贴图生成器等，菜单在 `Tools/草地/*` 和 `Tools/Noise Texture Generator`。
>
> 代码与着色器采用 MIT 协议；第三方美术素材（角色、模型、贴图、动画）版权归原作者，
> 仅作演示用途。详见文末「Third-party assets」。

---

## Demo scenes

All five scenes are already registered in **Build Settings**, in this order:

| # | Scene | What it demonstrates |
|---|-------|----------------------|
| 1 | `Assets/Scenes/Grass_Field.unity` | ~200k grass blades in **one indirect draw call**, compute-shader frustum/density culling, baked clump scatter, player-driven bending trail field |
| 2 | `Assets/Scenes/Fur_ShellTexturing.unity` | Classic shell fur on a sphere — 1–100 shells drawn with `DrawMeshInstanced`, one batch |
| 3 | `Assets/Scenes/Fur_PostProcessing.unity` | Screen-space fur: a `FurVector` pass encodes direction + length per pixel, a `ScriptableRendererFeature` blurs along it |
| 4 | `Assets/Scenes/Skybox.unity` | Layered stylized skybox — gradient, stars, moon, sun + glow, clouds, horizon, ground — driven by day/night scripts |
| 5 | `Assets/Scenes/Water_Dither.unity` | FFT displacement ocean with screen-door (dithered) water/terrain blending, shoreline foam and flow maps |

---

## Systems in depth

### Grass — GPU-driven field

`Assets/Grass/` contains the whole pipeline, split into authoring (`Editor/`), runtime (`Scripts/`)
and shading (`Shaders/`).

**Runtime:** `GrassField.cs` does three things per frame — push instance data to the material,
ask a compute shader to cull, then issue a single `DrawMeshInstancedIndirect`.

- **Why indirect instead of `DrawMeshInstanced`:** the latter is capped at 1023 instances per
  batch and needs one CPU submit per batch, so ~200k blades would be ~196 submissions. With
  indirect instancing the instance count lives in a GPU args buffer and the CPU stays out of it
  entirely.
- **Culling** is intentionally conservative: the compute pass tests the instance *root* plus a
  1.5 m margin, so 1 m-tall blades never pop at the screen edge.
- **Density falloff** drops from full density at `densityStart` to `farKeep` (default 35%) at
  `densityEnd`, then hard-cuts at `maxDistance` (default 42 m).
- **Sky blending** tints distant blades toward the skybox ground colour so the horizon has no
  hard edge.

**Interaction:** `GrassTrailSystem.cs` maintains a 1024² half-float RT holding a *world-space
push vector* (RG = X/Z), not a scalar strength. Storing direction rather than magnitude matters:
with a scalar, the shader would derive direction from "blade − player", and already-bent grass
would swing around as the player walks — like iron filings following a magnet.

It also avoids the classic "decay + stamp" ping-pong, which under URP averaged the feedback into
a flat blur. Instead the RT is cleared every frame and the last N footprints are re-stamped with
time-based fade — no read/write feedback, fully deterministic.

**Authoring (`Tools/草地/*`):**

| Menu | Tool | What it does |
|---|---|---|
| ① | `GrassBladeMeshBuilder` | Procedural blade mesh — 3 columns × 5 rows (15 verts / 16 triangles), matching UE's `Rectangle` blade topology; the centre column exists so the normals can form a mid-rib crease |
| ①b | — | Creates the grass material |
| ② | `GrassBaker` | Samples the terrain by density, applies clump hashing, slope limits and edge margins, then writes `GrassFieldData` + binary instance buffer |
| ②b | `GrassBaker` | Bake with default parameters |
| ③ | `GrassSceneSetup` | One click: 120 × 120 m terrain with a URP Lit material (the default terrain material renders pink under URP), plus a wired-up `GrassField` |
| ④ | `GrassInteractionSetup` | Adds a WASD test rig |
| ⑤ | `GrassRoadTool` + `GrassRoadRasterizer` | Spline road painting, rasterised into a mask |
| ⑥ | `GrassPaintTool` | Paint grass distribution directly onto a mask |
| ⑦ | `GrassTerrainLayerMaskSync` | Syncs the mask back to terrain layers |

Instances are stored in 32 m chunks (`GrassFieldData.GrassChunk`) with a packed 32-byte
`GrassInstance` record: `a` = world position + yaw, `b` = scale, two random seeds and a hue shift.

### Fur — two independent approaches

**Shell texturing** (`Fur_ShellTexturing.unity`): `FurInstancedRenderer.cs` pushes all shells into
*one* `DrawMeshInstanced` call and passes a `_LayerRatio` float array (0 → 1 across the shells) via
a `MaterialPropertyBlock`. The shader `URP_StaticInstancedFur.shader` uses that ratio to offset
along the normal, so density and length are tunable per shell without extra draw calls.

**Post-process fur** (`Fur_PostProcessing.unity`): a genuine two-pass pipeline built on URP render
features.

1. `Fur.shader` has a `FurVector` pass that draws *nothing* visible — it writes per-pixel hair
   instructions into `_FurVector`:
   `RG` = screen-space direction (biased into [0,1]), `B` = hair length scale, `A` = fur mask.
2. `FurRenderPassFeature.cs` allocates the RT and encodes the pass with the `FurVector`
   `ShaderTagId`.
3. `Fur_blur.shader` reads `_FurVector` and smears the colour along that direction.

The direction is deliberately **not normalised** in screen space: it preserves the projected
magnitude, so hair pointing at the camera projects to ~0 and produces no smear, while silhouette
hair (fully in the screen plane) gets the longest smear — which is exactly how real fur looks.

### Water — FFT surface and dithered ocean

`Assets/Codes/Water/FFTWaterSurface.cs` runs a Phillips-spectrum FFT entirely on the GPU:
bit-reversal + horizontal pass + vertical pass per frame, 256² tiles over a 200 m patch, with a
15 Hz editor preview so wave parameters are tunable without entering Play mode.

`PlanarReflection.cs` renders the scene once more through a mirrored camera. The details that make
it usable:

- oblique near-plane clipping (`CalculateObliqueMatrix`) removes everything below the surface,
  so you never see the backs of underwater geometry;
- culling is inverted for the mirrored pass, because mirroring flips triangle winding;
- the water's own layer is excluded from the reflection camera, preventing infinite recursion.

`Assets/Office/Shaders/Dither.shader` is the ocean look used by `Water_Dither.unity`: Beaufort
scale, flow maps, FFT displacement, Jacobian-based foam and shoreline foam, and a depth-driven
screen-door dither to blend water into the terrain instead of a hard intersection line.
`CliffTerrainBlendBinder.cs` / `CliffTerrainBlend.shader` handle cliffs meeting the terrain.
`Assets/Office/Reference/AnotherWater/` holds the reference implementation the dither approach
was studied from.

### Sky — a layered stylized skybox

`Assets/Shaders/Skybox/StylizedSkybox.shader` (827 lines) composes seven independent layers in a
single fragment, painted far-to-near:

```
gradient → stars → moon → sun + glow → clouds → horizon edge → ground
```

Every layer contributes through the same blend `color = lerp(color, layer, coverage)`, so any
layer can be switched off by setting its intensity to 0 without touching the others. The ground
is painted *after* the moon and sun so that anything below the horizon is occluded cleanly.

The moon is drawn by transforming the sky dome's vertices into the moon's **local space** and
using `local.xy` as UVs — which requires `Shader.SetGlobalMatrix("_MoonMatrix", …)` from C#.
`StylizedSkyboxMoonDriver.cs` feeds that matrix (so the moon's `+Z` is its position on the dome),
and `SkyTimeOfDay.cs` drives the day/night blend across the three colour sets.

### Toon / NPR — character shading set

`Assets/Shaders/Toon/` is a complete anime character shader:

- **`ToonCharacter.shader`** — 4-row ramp shadow (`addShadow` / `metalSpec` / `spec` /
  `directShadow`), dark-side tint, RG dual-channel normal (the character's `_N` map has an empty
  blue channel, so Z is rebuilt), packed mask (`P` = metal / smoothness / AO), per-pixel shadow
  map (`ST`), MatCap specular shared by metal / cloth / hair, segmented eyes (iris rim, catch
  light, eye shadow), and an inverted-hull outline with constant screen-space width.
- **Stencil outline system** — `ToonCharacterBodyCastStencil` / `…ReceiveStencil`,
  `ToonStencilPasses.shader`, `ToonStencil.hlsl`, `ToonShadowOverlay.shader`.
- **Hair** — `ToonAthenaHair.shader` and `ToonAthenaHairWithStencil.shader`.
- **Modular HLSL** — `ToonBase`, `ToonCharacterLitPass`, `ToonCharacterEdgePass`,
  `ToonCharacterHardRimPass`, `ToonConfig`, `ToonDataStruct`, `ToonDissolve`, `ToonMatcap`.
- **`Assets/Shaders/Zhanshuang/`** — a parallel NPR set (`NPR_ZS_Body`, `_Cloth_Code`, `_Eye_Code`,
  `_Face_Code`, `_Hair_Code`, `_Skin_Code`, `_PBR`, `_Alpha`).

### Editor tooling

- `NoiseTextureGenerator.cs` + `NoiseTextureGeneratorWindow.cs` — a `Tools/Noise Texture Generator`
  window that bakes Perlin/Worley/etc. into textures instead of round-tripping through an image
  editor.
- `RenderFeatures/` — `FurRenderPassFeature.cs` and `BlurRenderPassFeature.cs`, both wired into
  `Assets/Settings/URP-{Performant,Balanced,HighFidelity}-Renderer.asset`.

---

## Repository layout

```
Assets/
  Codes/            # runtime C# — Water (FFT, planar reflection, interaction),
                    # Fur instancing, NoiseGenerator, SkyTimeOfDay, FootGrounding
  Grass/            # flagship system: Editor/ (9 authoring tools), Scripts/, Shaders/, Data/
  Office/           # cliffs + ocean scene assets, Dither shader, AnotherWater reference
  Scenes/           # the 5 demo scenes
  Shaders/          # Toon/ (NPR character set), Water/, Skybox/, Fur/, Zhanshuang/
  Settings/         # URP pipeline + renderer assets, post-process profiles
  RenderFeatures/   # custom ScriptableRendererFeatures
  Materials/  Prefabs/  Models/  Characters/  Animations/  Textures/  Terrain/
Packages/           # manifest + lock
ProjectSettings/    # build settings (5 scenes), URP/quality settings
docs/legacy/        # archived notes from the Git+SVN era of this repo
```

---

## Getting started

1. Install **Unity 2021.3 LTS** through Unity Hub. The project was authored on `2021.3.45f1c2`
   (Mainland-China build); any `2021.3.x` works — open it with a different patch and Unity will
   offer to upgrade, which is safe for this project.
2. Open the project folder. The first import takes a few minutes (~600 MB of assets).
3. Open `Assets/Scenes/Grass_Field.unity` and press Play — `WASD` walks the player controller and
   bends the grass.
4. All five demo scenes are in **Build Settings** already, so *Build & Run* gives you a switchable
   tour.

If you only want to look at the code without the 600 MB clone:

```bash
git clone --depth 1 https://github.com/Theodore921/UnityDemo.git
```

The lock file resolves packages through the Mainland-China mirror (`packages.unity.cn`), because
the project is maintained on the China build of Unity. If that mirror is slow from your network,
switch the registry in `ProjectSettings/PackageManagerSettings.asset` to
`https://packages.unity.com` and re-resolve — no package versions need to change.

---

## Design notes

A few decisions worth calling out, all of which are explained in the source comments:

- **Grass culling is conservative by a fixed margin, not exact.** Exact per-blade culling is
  cheaper on paper but produces visible popping at the screen edge; a 1.5 m root margin costs
  almost nothing and removes the artifact.
- **The trail field stores a vector, not a strength.** Magnitude-only fields make already-bent
  grass rotate to face the player, because the shader has to invent a direction each frame.
- **The fur vector is unnormalised in screen space.** Normalising would give every hair the same
  smear length and lose the foreshortening that sells the effect.
- **The post-process fur pass writes no colour.** It only encodes instructions into an
  `ARGBHalf` RT, which keeps the expensive blur completely separate from shading.
- **The skybox paints ground last.** Because every layer is an independent `lerp` by coverage,
  ordering is the only thing that decides occlusion — painting ground before the moon would let a
  mirrored moon float above the horizon.

---

## Known limitations

- `Grass_Field.unity` is still **binary-serialised** (~6 MB) even though the project is set to
  *Force Text*; it was saved before that setting took effect. Open it and re-save to convert it to
  YAML (diffable, but larger).
- The repo carries its art (~600 MB) so it is cloneable as-is. A natural next step would be moving
  binaries to Git LFS, or shipping a slim demo build that downloads art separately.
- `Packages/manifest.json` includes `com.coplaydev.unity-mcp`, a git-URL dev dependency used for
  AI-assisted editing during development. It is not needed to open the scenes — remove that line
  if you don't want it.
- No automated tests yet: `Assets/Tests/` is absent, and validation is manual per scene.

---

## Third-party assets

The MIT license covers **code and shaders only**. The following are third-party and remain the
property of their authors — they are included for demonstration and **must be checked (or
replaced) before any commercial use**:

| Path | Origin |
|---|---|
| `Assets/Characters/Lizhiyan/`, `Assets/Models/Lizhiyan*.fbx` | Character model + textures from a third-party source |
| `Assets/Models/Mixamo/`, `Assets/Animations/` | Mixamo animation clips |
| `Assets/Office/Cliffs/`, `Assets/Office/Rocks/` | 4K PBR rock/cliff texture sets and a Sketchfab rock scan |
| `Assets/Shaders/Zhanshuang/` | NPR shader set by its original author |
| `Assets/Office/Reference/AnotherWater/` | Reference water implementation, kept for study |

References that shaped the shaders:

- `StylizedSkybox.shader` follows the layer breakdown in 知乎《风格化天空球》(Shin),
  <https://zhuanlan.zhihu.com/p/420268006>.
- `ToonCharacter.shader` borrows its structure from DanbaidongRP's `NPRToon` and the 4-row ramp
  convention described in the Vepley character documentation.

---

## License

[MIT](LICENSE) © 2026 Theodore — code and shaders. Third-party assets excluded, see above.
