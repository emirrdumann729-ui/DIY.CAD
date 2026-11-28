# DIY.CAD — Release notes

Detailed feature list: [ROADMAP.md](ROADMAP.md). Usage: [README.md](README.md).

## 0.9.4
- **Export dialog**: every output format in one place — File → Export... (Ctrl+E) and the Export button on the Features, Sketch, Drawing and Assembly toolbars. 48 entries in groups (DIY.CAD, 3D solid, 3D mesh / printing / visualization, 2D drawing, image, data / package); formats that do not apply right now or cannot be written are greyed out with the reason and a recommended alternative.
- **New DIY.CAD file types**: part / assembly / drawing templates (`.dcadt`, `.dasmt`, `.ddrwt` — they open as a new untitled document), drawing file (`.ddrw`, opens on the Drawing tab), library feature part (`.dclfp`) and forming tool (`.dcftp`).
- **New export formats**: STEP AP203 / AP214 / AP242 (schema selectable), OpenCASCADE BREP, 3MF, AMF, PLY, OFF, FBX (ASCII 7.4), glTF / GLB, VRML 97, XAML 3D, IFC4, a self-contained HTML 3D viewer, Adobe Illustrator (PDF-compatible AI), PNG / JPEG / BMP / TIFF / PSD, an XML report (features, mass properties, bill of materials) and a ZIP sharing package (DIY.CAD file + STL + HTML viewer + PNG + XML). Assemblies are written with each component's placement and color.
- **German, Russian and Chinese (Simplified) UI** next to Turkish and English: full dictionaries (~1300 strings each) and the Help text; Tools → Options → General → Language or `--lang=de|ru|zh`. Chinese text uses the system's CJK font.
- Smaller: Ctrl+E shortcut; the getting-started hint points to Export; the Plugins tab, plugin options, autosave interval unit and the material row in the feature tree are translated.

## 0.9.3
- **Protected region** for STL import: within a selected range along an axis, the protected layer of the section (e.g. the top part) and the strip inside it (e.g. center ±h) are only moved, not scaled; below the layer / at the strip edge and at the ends of the region they blend into the normal scaling (the strip has no effect outside the layer — the transform never folds). Details that mate with other parts, such as holes, slots and joints, keep their original size while the body grows around them. Layer and strip limits can vary along the axis as a profile.
- **Multi-region stretch**: `stretch` now also accepts a list of regions (separate + / − mm per region).
- For non-linear transforms (stretch, tapered growth, protection) the mesh is first cut along the transform's kink planes and then refined conformingly (no T-junctions) where the transform is not linear along an edge (`refine`, default 0.05 mm) — the mesh stays closed and large triangles are not bent.
- Import panel: protected region on / off, axis, range, blend length; the summary line shows stretch regions, tapered growth and the protected region.
- Macro `rebuild()` waits up to 15 minutes for long imports (it used to stop waiting after 2 minutes).
- Real-part test: an RC aircraft fuselage was scaled to 800 mm while the part where the wing sits (slot, holes, seating surfaces) kept its original size.

## 0.9.2
- **STL import** (binary / ASCII): in OpenCASCADE the triangles are sewn into a solid (later features, split and STEP export work), in the CSG kernel it is merged as a mesh body.
- Import transform: **per-axis scale** (X/Y/Z), scale center, translation and, for STL, **regional stretch** (a selected range along an axis stretches proportionally, everything after it shifts; entered as mm to add to the final length). Per-axis scale also works for STEP / IGES.
- **Tapered section growth** for STL: in a selected region along an axis, a linearly increasing amount of mm is added to each section (about the section center; reference profile from the ends), straight tapers stay straight — to make two parts meet at different sections.
- Macro API: `await m.export(...)` waits for the OpenCASCADE export to finish.
- `.dcad` / `.dasm` paths given after `--` on the command line are opened too.
- Real-part test: a 6-part RC aircraft fuselage (STL) was resized to 800 mm length and a 120 × 120 mm nose.

## 0.9.1 — Phase 9 (complete)
- **Background mesh processing**: processing of the model from the kernel (vertex welding, adjacency, edges, smoothed normals) runs on a WorkerThreadPool thread; longest UI freeze on a 120k-triangle model 1072 ms → 234 ms. Display normals were sped up with a compressed adjacency list. OpenCASCADE already runs in a separate process.
- **Large assemblies**: automatic level of detail for component meshes (LOD, `ImporterMesh.generate_lods`); large assembly mode (auto / off / on): edges only on the selected / hovered component.
- **Plugins**: `setup(api: PluginApi)` scripts in `plugins/` and in the user folder; command buttons on the "Plugins" tab (shortcuts / mouse gestures assignable), custom panels, model / document events; enable / disable in Options → Plugins. Samples: Quick Box, Part Info.
- **Translation**: formatted status / panel messages and the Help text in English (dictionary ~1170 strings).
- **Packaging**: Windows export preset (`export_presets.cfg`, icon `icon.ico`), `Paketle.bat` (portable build + Inno Setup 6 installer), `installer/DIYCAD.iss` (per-user install, .dcad / .dasm association, optional OpenCASCADE setup). The installed version looks for the OpenCASCADE, macro and plugin folders next to the .exe.
- `.dasm` files open from the command line (file association).

## 0.9.0 — Phase 9 (part 1)
- Auto-save, crash recovery, recent files, .bak backup on save.
- Customizable keyboard shortcuts (170+ commands), mouse gestures (8-way ring), dark / light theme, UI scale, Turkish / English UI.
- GDScript macros: run, record, macro from part, `--macro=` command line.

## 0.8.1 — Phase 8 (complete)
- Surface modeling (extruded / revolved / loft / planar / offset surface, knit, thicken, trim), linear static analysis (FEA, von Mises / displacement map), draft analysis and parting line, 2.5-axis CAM G-code, visualization (HDRI, shadows, PBR, decals), hem.

## 0.8.0 — Phase 8 (part 1)
- Sheet metal (base / edge flange, K-factor, flat pattern and DXF), weldments (profile library, miter / butt / T-joints, cut list), configurations and design table (CSV).

## 0.7.1 — Phase 7 (complete)
- Sub-assemblies, cam mate, component patterns, collision detection while dragging, assembly drawings and auto balloons, new part in assembly context.

## 0.7.0 — Phase 7
- Assembly document (.dasm), standard / advanced / mechanical mates, rigid-body solver, interference detection, exploded view, assembly bill of materials, fastener library, motion study, assembly STEP export.

## 0.6.0 — Phase 6
- Drawings: sheet and title block, standard / projected / section / detail / auxiliary / broken views, hidden-line removal (HLR), smart dimensions and model items, tolerances, GD&T, surface finish, weld symbols, BOM, revision table; PDF / SVG / DXF export.

## 0.5.x — Phase 5
- Reference geometry, extrude end conditions and thin feature, sweep and loft (with guide curves), patterns and mirror, hole wizard, dome, helix / spiral, rollback bar and feature reordering, projected curve, wrap, emboss, coordinate system.

## 0.4.x — Phase 4
- OpenCASCADE (B-rep) kernel (Python helper process), topological naming, fillet / chamfer / shell / draft / rib, multi-body, STEP / IGES import and export.

## 0.3.x — Phase 3
- Trim / extend / offset / mirror, sketch fillet / chamfer, polygon, slot, spline, text, ellipse, parabola, sketch patterns, blocks, region selection, global variables and equations, 3D sketch.

## 0.2.x — Phase 2
- Unit systems, constraint solver, smart dimension, geometric relations, definition-state colors, measure, material library and mass properties.

## 0.1.x — Phase 0–1
- UI skeleton, CAD camera, document model; sketch mode and basic tools, extrude / revolve / cut, feature tree, STL / OBJ / DXF / SVG export.
