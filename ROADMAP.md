# DIY.CAD — Roadmap

A **parametric, feature-based** CAD program written in Godot 4.7.


---

## Architecture decisions

| Topic | Decision | Why |
|---|---|---|
| Engine | Godot 4.7.1 | Ready-made 3D rendering, UI system, cross-platform |
| Language | GDScript first, C++ (GDExtension) later for heavy work | Fast progress; performance-critical parts can move to C++ |
| Internal units | **Millimeters** and **degrees** | All data is stored in mm and converted to the selected unit on screen |
| Geometry kernel | Phases 1–3: Godot CSG (Manifold library). Phase 4: **OpenCASCADE (OCCT)** | CSG gives a quick start; fillet/shell/STEP need a real B-rep kernel |
| Data model | Feature tree → full "rebuild" on every change | Parametric history: each feature is applied to the result of the previous ones |
| File format | `.dcad` (readable JSON) | Easy to debug, version-control friendly |
| Undo / Redo | Document snapshots | Simple and robust; can move to a command-based approach later |

### Folder layout

```
DIY.CAD/
  project.godot
  scenes/main.tscn          Main scene
  src/main.gd               Application: menus, commands, modes
  src/core/                 Document, feature, sketch, plane, units (engine-independent data)
  src/kernel/               Geometry kernel (CSG) + mesh utilities
  src/view/                 3D view, camera, sketch editor, axis triad
  src/ui/                   Feature tree, property panel, number field, icons
  src/io/                   Export: STL, OBJ, DXF, SVG
  tests/selftest.gd         Automated tests (from the command line)
```

---

## Phase 0 — Basic skeleton ✅
- [x] Godot project, main scene, folder layout
- [x] UI layout: menu, command bar, feature tree, property panel, 3D view, status bar
- [x] CAD camera: rotate / pan / zoom toward the cursor, standard views, fit, perspective/orthographic
- [x] Origin and the three main planes (Front, Top, Right), XYZ axis triad
- [x] Document model, JSON save/open, undo/redo

**Done when:** the program starts, you can navigate the model space, and an empty part can be saved and opened.

## Phase 1 — Draw a simple part and export (MVP) ✅
- [x] Sketch mode: draw on a plane or planar face, the camera turns normal to the plane
- [x] Sketch tools: line (chained), centerline, corner rectangle, center rectangle, circle, center-point arc
- [x] Grid and endpoint / origin snapping, horizontal/vertical snapping
- [x] Shared points: connected lines move together, point dragging
- [x] Numeric input for the selected entity in the panel (with expressions: `25.4*2`, `12,5`, `1in`)
- [x] Closed contour detection, nested contours = holes
- [x] Extruded Boss/Base: Blind, Mid Plane, Through All; flip direction
- [x] Extruded Cut
- [x] Revolve / Revolved Cut (about a sketch axis or centerline)
- [x] Feature tree: edit, edit sketch, suppress, delete, rename
- [x] Live preview (while the property panel is open)
- [x] Export: **STL** (3D printing), **OBJ**, sketch as **DXF** / **SVG** (laser cutting), PNG screenshot

**Done when:** you can draw a plate, cut a hole, add a cylinder on top, export STL and open it in a slicer (Cura etc.).

## Phase 2 — Dimensioning and units ✅
- [x] Unit system selection: MMGS, CGS, MKS, IPS (inch-pound-second), custom; decimal precision (one click from the status bar)
- [x] Document properties window (unit system, length/mass unit, decimal places, material) — units are saved with the document
- [x] **Constraint solver**: weighted Levenberg-Marquardt, degree-of-freedom (DOF) analysis, automatic undo of conflicting changes
- [x] **Smart Dimension**: linear (aligned/horizontal/vertical depending on cursor position), radius, diameter, angle, point-line distance
- [x] Driving and driven dimensions; on-screen dimensions with arrows, double-click for the value box
- [x] Geometric relations: coincident, horizontal, vertical, parallel, perpendicular, tangent, concentric, equal, midpoint, symmetric, fixed, collinear
- [x] Automatic relations while drawing: horizontal/vertical inference, snapping to endpoint/line midpoint/entity, horizontal+vertical on rectangles
- [x] Relation-preserving dragging (point, line move, circle radius); redundant relation/dimension warning
- [x] Sketch definition colors: blue (under-defined), black (fully defined), red (over-defined); (-)/(+) prefix in the tree
- [x] Measure tool: distance, normal distance, angle, area, perimeter, coordinates
- [x] Material library (21 materials: metals, 3D-printing plastics, wood) and **mass properties** (volume, area, mass, center of gravity, inertia tensor, principal moments)

**Done when:** drawing a rectangle and dimensioning it "60 x 40" fixes the sketch, and switching to inches shows all values correctly. ✔ (Verified by automated tests.)

## Phase 3 — Advanced sketch tools and parameters ✅
- [x] **Trim** (power trim: the clicked piece is deleted between the nearest intersections; ends are joined with coincident relations)
- [x] **Extend** (a line up to the first entity it meets)
- [x] **Offset**: connected chains with their corners; all edges driven by a single offset dimension, with preview
- [x] **Mirror**: about a centerline, with symmetric relations (the copy changes when the original changes)
- [x] **Sketch fillet / chamfer**: tangent relations + radius/distance dimension; the old corner remains as a "virtual sharp", attached dimensions are kept
- [x] **Polygon** (construction circle + equal sides), **straight slot** (tangent arcs), **spline** (through all points, open/closed), **sketch text** (from font outlines; emboss/engrave)
- [x] Linear / circular sketch patterns, move / copy / rotate / scale (internal relations are copied)
- [x] Toggle construction geometry
- [x] Global variables and **equations** (`"D1@Taslak1" = width / 2`): type `=expression` in the value box; extrude depth / revolve angle can also be driven by equations; Turkish variable names are supported
- [x] **Ellipse** (center + major axis end + minor semi-axis; semi-axes are dimensioned, angle/center in the panel) and **parabola** (vertex + focus + two ends; focal distance is dimensioned, can be extruded as a closed contour)
- [x] **Convert entities**: the boundary edges of the selected model face come into the sketch as fixed lines/arcs (from real B-rep edges in the OpenCASCADE kernel; mesh-based in the CSG kernel)
- [x] **Sketch blocks**: selected entities become a rigid block (moves/rotates as a whole when dragged), explode and copy
- [x] **Region selection from intersecting contours** (contour select): regions formed by intersecting curves are clicked to select them for extrude/revolve
- [x] **3D sketch (basic)**: line chains on the XY/XZ/YZ planes (switched with Tab), axis lock, point snapping, coordinate editing

## Phase 4 — Moving to a B-rep kernel (OpenCASCADE) ✅
CSG only produces triangle meshes; fillets, shells, STEP etc. need **real face/edge topology**.
- [x] OpenCASCADE connection: a **Python helper process** that needs no C++ compiler (`occ/occ_server.py`, OCP / OCCT 8.0, project-local `occ_env`, setup: `OCC_Kur.bat`). JSON over stdin/stdout with Godot; large requests go through a temporary file. (Chosen instead of GDExtension; a C++ module with the same protocol is possible later.)
- [x] Same kernel interface (`GeoKernel`): Phase 1–3 features (extrude, revolve, cut, region selection, ellipse/parabola/spline/text profiles) work with **real curves** in OCC; automatic CSG fallback when OCC is missing/crashes. Tools → Geometry kernel: Auto / OpenCASCADE / CSG
- [x] Double-precision geometry, exact volume/area/inertia (GProp)
- [x] **Topological naming**: every face gets a persistent name from the feature + sketch entity that created it (e.g. `F3:s:12`, `F3:b:10`); names are carried through every operation with the OCCT history (Modified/Generated/Deleted). Edges are referenced by their neighboring face names, faces/bodies by name; if a name cannot be found it falls back to a geometric signature. A sketch drawn on a face is attached to its support face: when the model changes, the sketch plane moves with the face
- [x] **Fillet** (constant radius), **Chamfer** (equal distance), **Shell** (selected faces open; hollow body when no face is selected; inward/outward) — select by clicking edges/faces, the body before the feature is shown while selecting
- [x] **STEP / IGES export**, **STEP / IGES import** (surface-based IGES is sewn into a solid, scale), high-quality STL (deviation/angle presets, binary/ASCII)
- [x] Convert entities from B-rep edges: lines, circles, arcs, ellipses come in as real entities
- [x] **Variable-radius fillet** (linear along the edge), **two-distance** and **angle-distance chamfer** (flip direction)
- [x] **Draft**: mold draft on faces relative to a neutral face, pull direction can be flipped
- [x] **Rib**: from an open sketch line, equal thickness on both sides; ends extend automatically until they hit the body, material side can be flipped
- [x] **Multi-body**: unchecking "Merge result" in extrude/revolve makes a separate body; **Combine Bodies** (add / subtract / common), **Move/Copy Body** (translation + rotation about an axis), **Split** (main plane + offset, side to keep); fillet/chamfer/shell/draft apply only to the relevant body

## Phase 5 — Advanced 3D features ✅
- [x] **Reference geometry**: plane (offset, angled, 3 points; based on a main plane / reference plane / model face), axis (main axis, two points, edge or cylinder axis, intersection of two planes), point. Sketches attach to reference planes and move when the plane changes; revolve and patterns can use reference axes
- [x] **Extrude end conditions**: Up To Next, Up To Vertex, Up To Surface, Offset From Surface, Two Directions (Direction 2: blind / through all / up to next), draft angle (in/out), **thin feature** (open or closed sketch; mid / one direction / other direction)
- [x] **Sweep** (boss / cut; path: sketch chain, 3D sketch or helix) and **Loft** (boss / cut, ruled or smooth)
- [x] **Linear** (two directions), **circular**, **table-driven** patterns and **mirror** — of features (extrude, revolve, sweep, loft, hole) or of all bodies
- [x] **Hole Wizard**: simple, counterbore, countersink, tapped; ISO (M2–M24, ISO 273 fit classes) and ANSI (#4–1/2 UNC); through all / blind (118° drill point); cosmetic thread on tapped holes (dashed circle)
- [x] **Dome**, **helix** (pitch/revolutions/height, clockwise, start angle)
- [x] **Rollback bar** (draggable; new features are inserted before the bar), reorder features by **dragging** or Move up/down (parent/child order is kept), **Parent / Child** window
- [x] **Reference plane tangent to a surface** (at a picked point on a cylinder/cone/sphere/plane) and **coordinate system** (origin + X/Y axes; mass properties are reported relative to it)
- [x] **Guide curve** (the profile scales to touch the guide) and **twist angle** in sweeps; **guide curve** in lofts
- [x] **Curve-driven pattern** (along a sketch chain, 3D sketch, helix or projected curve; equal spacing or fixed spacing; rotation following the curve)
- [x] **Spiral** (planar) and **tapered helix**, **projected curve** (projects a sketch curve onto a face; usable as path/guide/pattern curve), **wrap** (emboss / deboss / scribe on a cylinder, arc length preserved), **emboss / engrave** (constant thickness following the surface)

## Phase 6 — Drawings ✅
- [x] **Drawing** tab: drawing sheets are stored in the part file (`drawings`), work with undo/redo; multiple sheets
- [x] Sheet sizes **A4–A0** and **ANSI A–E**, landscape/portrait, **ISO / ANSI** standard; border, centering marks and **title block** (company, title, drawing no., drawn by, checked by, date, material, scale, weight — material and mass from the model automatically)
- [x] **Standard 3 views + isometric** (automatic scale and layout), **first angle (ISO) / third angle (ANSI)** with projection symbol; projected views re-orient when the angle changes
- [x] Model view (front, back, top, bottom, right, left, isometric, dimetric), **projected view** (on the clicked side), **section** (section line with two clicks; hatch, A-A label, arrows, flippable direction), **detail** (circle, magnification), **auxiliary** (normal to an edge), **broken view** (multiple breaks, zigzag limits)
- [x] **Hidden-line removal (HLR)**: visible / hidden / tangent edges with OpenCASCADE HLRBRep; hidden lines that coincide with visible ones are suppressed. Per-view hidden lines (dashed / removed) and tangent edges (show / hide); approximate view from mesh edges without OCC
- [x] **Smart dimension** (vertex, circle center, circle, edge snapping; horizontal / vertical / aligned, diameter, angle), **model items** (sketch dimensions into parallel views; associative — the drawing updates when the sketch changes), **reference dimension**, **tolerances** (symmetric, deviation, limit, fit such as H7), text override
- [x] **GD&T** feature control frame (14 characteristics, Ø zone, MMC/LMC, datums), **datum** symbol, **surface finish** (Ra; machined / no removal / any), **weld symbol** (fillet / V butt; arrow side / other side / both, all around, tail note)
- [x] **Center mark** (single / all circles in a view), **centerline**, **notes** (multi-line, with leader), **balloons**, **bill of materials (BOM)**, **revision table**
- [x] Move views and annotations by dragging (projected children stay aligned), free-space search for automatic placement, Delete / Esc
- [x] Output: **PDF** (vector, multi-page, embedded TrueType subset — Turkish characters in all viewers), **SVG**, **DXF** (R12, layers GORUNUR / GIZLI / EKSEN / OLCU / TARAMA / METIN, line types, cp1254), **DWG** (convert the DXF with AutoCAD or the free ODA File Converter), **print** (the PDF opens in the default application)

## Phase 7 — Assemblies ✅
- [x] **Assembly document** `.dasm` (JSON; part paths relative to the assembly), File → New Assembly / Open, its own undo / redo history; **Assembly** tab and toolbar
- [x] **Insert component** (part file; the same part is built once, instances `Name<1>`, `Name<2>`), the first component is **fixed** (f), fix / float, hide, suppress, numeric position; under-defined components marked (-) in the tree
- [x] Parts are built independently of the main part (stored by key in the OCC server; separate kernel in CSG); edit with **Open Part**, return with the Assembly tab (the part is saved and refreshed in the assembly)
- [x] **Standard mates**: coincident, parallel, perpendicular, tangent, concentric, distance, angle, lock — face / edge / main plane / origin references, suggested types based on the selection (★), flip alignment / direction
- [x] **Advanced**: width, symmetric, distance limit, angle limit, slot; **mechanical**: hinge, gear (ratio from radii), rack and pinion, screw (pitch)
- [x] **Rigid-body solver**: 6 DOF per component, Levenberg-Marquardt, per-component **DOF analysis**, conflicting / unsatisfied mate warning (⚠); continuous (multi-turn) angle for mechanical mates
- [x] **Dragging to move / rotate** components (respecting mates), numeric translation and rotation
- [x] **Interference detection** (OpenCASCADE common volume; red volumes and a volume list), **exploded view** (steps, automatic explode deriving directions from mates, animation, explode lines), **assembly bill of materials** (quantity, material, mass; CSV), **mass properties**, assembly **STEP** export
- [x] **Fastener library**: hex bolt ISO 4017, nut ISO 4032, washer ISO 7089 (M3–M24), dowel pin, deep-groove ball bearing (60xx / 62xx) — size can be changed in the panel
- [x] **Motion study** (motor): rotation about the selected axis in rpm, mates (gear, screw, rack...) transfer the motion, stops when locked
- [x] **Sub-assemblies**: `.dasm` inserted as a component, rigid group (sub-parts merged into one model; their faces can be mated), nested sub-assemblies, "parts only" / "top level" in the BOM, open sub-assembly
- [x] **Cam mate**: follower (point, sphere, roller/cylinder) touches the cam profile; the profile is extracted automatically from the tangent region of the cam's side face, works with the motion study
- [x] **Component pattern**: linear (X/Y/Z or direction of an edge/axis/face on the model, spacing) and circular (axis, total angle); instances follow the seed, count can be changed, a deleted instance is skipped
- [x] **Collision detection while dragging** (OpenCASCADE): the component stops at the last collision-free position the moment it collides; touching faces do not count as collisions
- [x] **Assembly drawings**: Drawing tab in assembly mode; views from the assembly compound (HLR, section, detail...), assembly name/mass in the title block, bill of materials table with assembly items, **auto balloon** (one per item, targets distributed); the drawing is stored in the `.dasm`
- [x] **New part in assembly**: a part file is created and placed at the assembly origin; while editing it the other components appear semi-transparent in the part's coordinates and sketches can be started on their planar faces (in-context design)

## Phase 8 — Special modules ✅
- [x] **Sheet metal**: **base flange** (closed profile → plate; open line chain → bent sheet with bend radius, material side, mid plane), **edge flange** (click base edges, multiple edges, angle, length, bend radius, direction, end gaps; the edge is tied to the base sketch through its topological name), **K-factor** and bend allowance BA = A·(R + K·T), **flat pattern** (flat sheet display) and **flat pattern DXF** (bend lines on the EKSEN layer, UP/DOWN angle notes)
- [x] **Hem**: 180° edge flange preset (R = T/2, length 8 mm), by clicking an edge
- [ ] Sheet metal, later: miter flange, sketched bend, flange on edge flange, corner relief
- [x] **Weldments**: profile library (square / rectangular tube, pipe, angle, UPN, IPE, flat bar), **structural members** from sketch or 3D sketch lines (each member a separate body, profile rotation), **miter** or **butt** corners, the vertical member runs through at three-way corners, **trimming at T-joints**, **cut list** (profile, length, cut angles, quantity, mass; CSV)
- [x] **Surface modeling**: extruded / revolved / loft / planar surface, offset surface, **knit** (converted to a solid if closed), **thicken** (one side / mid, merge with solid), **trim** with a plane; surfaces are kept as zero-thickness bodies in the same part as the solids, later solid features preserve them
- [ ] Surfaces, later: swept surface, boundary surface, fill, trim with a surface, extend
- [x] **Configurations** (dimension values, feature depths/angles and suppression states; the active configuration at the tree root) and **design table** (CSV import / export; Excel opens the CSV)
- [x] **Simulation (FEA)**: linear static analysis (numpy + scipy in the server; voxel hexahedra with incompatible modes, sparse direct solver), **fixed faces** and **forces** (normal to the face / along an axis) by clicking faces, E / ν / yield from the material, **von Mises** and **displacement** color maps, deformation scale, factor of safety, support reactions (verified within 0.2% against the cantilever FL³/3EI)
- [ ] FEA, later: tetrahedral mesh, pressure / gravity loads, assembly analysis, modal / thermal analysis
- [x] **Visualization**: studio / daylight / night environments and **HDRI** panorama loading, shadowed sun + shadow-catcher floor, SSAO / SSR / glow, **PBR** surface from the material (metal / matte / glossy), exposure, **decals** (pick an image, click a face), **render PNG** at 2× resolution
- [x] **Mold tools**: draft (pull angle) analysis — positive / negative / draft-required faces colored, area ratios, possible **parting line**
- [x] **CAM (2.5-axis)**: outer contour / inner contour / pocket toolpaths from sketch contours (tool-radius offset, stepover, islands), step-downs, Z0 at part top or sketch plane, **G-code** (ISO, G21) and time estimate
- [ ] Mold / CAM, later: core-cavity split, shrinkage allowance, 3-axis surface milling, tool library

## Phase 9 — Professional features ✅
- [x] **Auto-save** (configurable interval, parts + assemblies, records keyed by process id), **crash recovery** window, **recent files** (menu + empty-part panel), **.bak backup** on save
- [x] **Keyboard shortcut** customization (170+ commands registered automatically: menus, toolbars, sketch tools; contexts General / Sketch; conflict resolution; menus show live shortcuts), **mouse gestures** (right button + direction → 8-way ring; assignable per part / sketch / assembly context), **dark / light theme**, **UI scale**, **Turkish / English** UI (Godot auto-translation, `i18n/en.txt`, ~1050 strings)
- [x] **Macro API** (GDScript: `func run(m: MacroApi)`; sketch / feature / export helpers, `await m.rebuild()`), **macro recording** (added features → `m.add_raw`, id remapping), **macro from part**, sample macros (`macros/`), command line `--macro=`
- [x] Unit tests: 10 test groups (solver, sketch operations, drawings, assemblies, special modules, Phase 9, B-rep, end-to-end UI × 2 kernels)
- [x] **Performance**: processing of the kernel result (vertex welding, adjacency, edges, smoothed normals) on a **background thread** (WorkerThreadPool; longest freeze 1072 → 234 ms), fast normals with a compressed adjacency list; **LOD for large assemblies** (ImporterMesh.generate_lods) and large assembly mode
- [x] **Release notes** (CHANGELOG.md), **Windows packaging**: export preset + icon, `Paketle.bat`, Inno Setup installer script (per-user install, file association, optional OpenCASCADE setup); the installed version looks for the `occ_env` / `occ` / `macros` / `plugins` folders next to the .exe
- [x] **More translation**: formatted status / panel messages and the Help text in English (~1170 strings, format specifiers verified by tests); **plugin interface** (PluginApi: command + button, custom panel, events, macro API; enable / disable in Options; 2 sample plugins)
- [x] **Export dialog** (v0.9.4): all output formats in one place (Ctrl+E), 48 entries; new DIY.CAD file types (templates, drawing file, library feature, forming tool) and new writers (STEP schemas, BREP, 3MF, AMF, PLY, OFF, FBX, glTF / GLB, VRML, XAML, IFC4, HTML viewer, AI, images, XML, ZIP)
- [x] **German, Russian and Chinese UI** (v0.9.4): full dictionaries (~1300 strings) and Help; format specifiers, trailing spaces and two-line button labels verified by tests

---

## Features → Phase mapping

| Feature | DIY.CAD phase |
|---|---|
| Sketch, Line, Rectangle, Circle, Arc, Centerline | 1 ✅ |
| Extruded Boss/Base, Extruded Cut, Revolved Boss/Cut | 1 ✅ |
| STL/OBJ export, DXF sketch export | 1 ✅ |
| Smart Dimension, Relations, Units, Mass Properties, Measure | 2 ✅ |
| Trim/Extend/Offset/Mirror, Sketch Fillet/Chamfer, Spline, Polygon, Slot, Text, Patterns, Equations | 3 ✅ |
| Ellipse, Convert Entities, Blocks, Contour Select, 3D Sketch | 3 ✅ |
| Fillet, Chamfer, Shell, Draft, Rib, STEP/IGES, Multi-body | 4 ✅ |
| Sweep, Loft, Patterns, Mirror, Hole wizard, Reference Geometry | 5 ✅ |
| Drawings, Section/Detail Views, BOM, GD&T | 6 ✅ |
| Assemblies, Mates, Exploded View, Interference, fastener library | 7 ✅ |
| Sheet Metal, Weldments, Configurations | 8 ✅ |
| Surfaces, static analysis, visualization, draft analysis, CAM | 8 ✅ (basic) |
| Options, Customize, Macros, Add-ins, Auto-recover, Large Assembly Mode | 9 ✅ |

## Known limitations
- All Phase 5 features require the OpenCASCADE kernel (reference geometry and the rollback bar also work in CSG). For patterned tapped holes the cosmetic thread is drawn only on the first hole.
- Wrap works only on cylindrical faces and the sketch plane must be parallel to the cylinder axis; guided sweeps support a single guide curve, holes in the profile are ignored.
- Twisted sweeps are built as smooth lofts through intermediate sections (approximate surface); emboss/engrave uses an offset of the whole body and may fail on very complex bodies.
- In sweeps the profile must be at the start of the path and normal to it; sweeps along sharp-cornered 3D sketch paths may fail.
- In the CSG kernel geometry is triangle-mesh based; circles are split into 128 segments. In the OpenCASCADE kernel geometry is exact, only the display is triangulated.
- The OpenCASCADE kernel requires Python 3.11–3.13 and `occ_env` (~240 MB, including numpy + scipy for static analysis); it starts in ~1 s on first launch, during which the model is shown with CSG.
- Topological names are based on sketch entity ids: if an entity is deleted and redrawn, the names of the faces derived from it change and references fall back to geometric matching. If a face is split in two, both pieces carry the same name and the closest one is chosen.
- A sketch on a face follows the support face only when it moves along its own normal (if the face rotates/tilts, the plane stays in place).
- Ribs use OCCT LinearForm: the profile must start outside the body and reach it; may fail with very complex profiles.
- In the CSG kernel a sketch drawn on a face copies the face's **plane**; if the underlying part changes the sketch stays in place (in the OpenCASCADE kernel it moves with the support face).
- Dimensions are shown on the 3D model only while editing a sketch (no 3D model-based dimensions); model items can be brought into drawings.
- Sheet metal and weldments require OpenCASCADE. Edge flanges can only be added to the top / bottom edges of a flat (closed-profile) base flange; the bend is made "outward" (the base length does not change). While the flat pattern is shown, cut/hole features after the base flange are not carried into the flat pattern. An open-profile base flange must consist of straight lines only.
- In weldments members are straight lines (no arc paths); corner fillets and weld beads are not modeled; in the cut list the length of mitered members is the centerline length.
- Configurations cover dimension / depth / angle values and suppression states (material, color and feature type changes are not covered).
- Surface features and static analysis require OpenCASCADE; FEA also needs numpy + scipy in `occ_env` (`OCC_Kur.bat` installs them). Because the mesh is voxel-based, curved faces are approximated with steps: stress concentrations (hole edges, inner corners) depend on the mesh density, results are for preliminary sizing. Loads are forces evenly distributed over faces (no pressure / moment); single parts only (no assembly analysis).
- Surface trim is only against standard planes (with offset); knit only joins surfaces whose edges coincide (within tolerance).
- CAM is 2.5-axis: only (planar) sketch contours are machined, the toolpath is the tool center, there is no lead-in/out ramp and no cutter compensation (G41/G42); check the G-code in a simulator before running it on a machine.
- Visualization is real-time (Godot Forward+): no ray tracing; the HDRI panorama is used as ambient light and reflection, decals are not saved (per session).
- In the translated UIs (English, German, Russian, Chinese) the whole interface is translated; feature names (Ekstrüzyon1...), default part / configuration names, sheet-metal bend notes and error messages coming from the OpenCASCADE server stay Turkish. Drawing sheets follow the UI language, except Russian and Chinese, which use English (DXF is written in code page 1254 and PDFs embed Arial, which has no Chinese glyphs). Theme changes apply after a restart.
- Macros are GDScript code with access to the whole application: only run macros you trust. Macro recording records only **added** features (edits / deletions are not recorded).
- Auto-save may lose the latest changes within the save interval; drawing edits are part of the part's record.
- In the CSG kernel Boolean operations are computed with Godot's CSG nodes on the main thread (CSG does not work outside the scene tree); parts with many holes may freeze briefly — the OpenCASCADE kernel is not affected because it runs in a separate process. LOD is chosen with Godot's screen-size criterion in perspective and orthographic views.
- The installer needs the Godot export templates and Inno Setup 6 (`Paketle.bat` explains what to do if they are missing). In the installed version OpenCASCADE is also set up with Python + `OCC_Kur.bat`; Python is not bundled.
- Plugins and macros have access to the whole application; only put plugins you trust in the `plugins/` folder.
- Assemblies: interference detection and assembly STEP export require OpenCASCADE. In the CSG kernel mate references are limited to planar faces and fitted cylinders (no edge selection). Gear / screw / rack angles are measured from the position at the time the mate was created; gear geometry is not modeled (the library bearing has no balls, bolts have no threads — simplified solids). Sub-assemblies are rigid (no flexible sub-assemblies); mates inside a sub-assembly are not solved in the parent assembly. In in-context editing the faces of other components can only be used as sketch planes (no convert entities / associative references). Collision detection runs asynchronously: during fast dragging the component returns to the previous collision-free position.
- Drawings: section views require the OpenCASCADE kernel; only full (straight) sections are available (no stepped/half/broken-out sections). Model items are limited to sketch dimensions (feature depths are not brought in). Printing goes through PDF, not directly. DWG is not written directly.
- In drawings text width is estimated rather than measured from the font (real glyph widths are used in PDFs); alignment of very long notes may shift by a few mm.
- The measure tool selects faces and vertices; B-rep edge selection and cylinder radius measurement are not yet wired into the measure tool (the kernel provides this information).
- There is no tangent arc tool yet (use an arc + tangent relation).
- Extend works on lines and arcs; trim works on lines/circles/arcs (splines, ellipses and parabolas can be used as cutters but cannot be trimmed themselves).
- Offset does not support text; patterned copies are positioned freely (under-defined).
- 3D sketches currently consist only of straight lines; there are no 3D relations/dimensions.
- Entities brought in with convert entities are fixed; the sketch does not update when the part changes (in the CSG kernel curves are split into short lines).
- Text is drawn with the program's default font; font selection in a later version.
- In the CSG kernel, when two exactly coincident curved faces are merged, a hairline seam may rarely remain (does not happen in the OpenCASCADE kernel).
- Lines are 1–2 pixels wide on screen; there is no edge thickness setting yet.
