# {{PROJECT_NAME}}: whitebox model and dimensions

An empty-room whitebox model scanned with iPhone LiDAR (Apple RoomPlan), intended for interior modeling in Blender.
Scanned {{DATE}} · {{ROOM_COUNT}} room(s) · about {{TOTAL_AREA}} m² in total.

## Files

| File | Purpose |
|---|---|
| `scene.json` | **The authoritative structured data**: rooms, walls, openings, fixtures, notes. Units: meters |
| `build_whitebox.py` | Blender script that rebuilds the whitebox at true scale from `scene.json` (recommended) |
| `whitebox.obj` / `.mtl` | The same whitebox as OBJ; imports directly into Blender |
| `whitebox.usda` | The same whitebox as USD (Z up, meters); imports directly into Blender |
| `roomplan_original.usdz` | Apple RoomPlan's original parametric model with furniture, for reference only |
| `floorplan.png` / `.pdf` | Top-down dimensioned floor plan in millimeters |
| `photos/` | On-site photos. Files starting with `AUTO_` were taken automatically while scanning; others were taken manually. Positions and directions are in `sitePhotos` in `scene.json` |

## Coordinates and units

- Units: meters (numbers on the floor plan and in notes are millimeters)
- Right-handed, **Z up**, same as Blender; floor at z = 0
- Importing `whitebox.obj` with Blender's default settings (Forward -Z, Up Y) gives exactly the coordinates in `scene.json`

## scene.json essentials

- `rooms[].floorPolygon`: floor outline (counter-clockwise); `height` is the ceiling height
- `walls[].start / end`: the line of the **room-side face** of the wall; `thickness` extrudes toward `outward` (away from the room)
- `walls[].height`: wall height. **A wall lower than its room's ceiling height usually means a beam or dropped ceiling there**; the value is the height of its underside (beams are not detected separately; this is an approximation)
- `walls[].measuredLength`: wall length measured with a tape by the user. **Prefer it when present**
- `openings[]`: door and window openings. `centerOffset` is the distance from the wall `start` to the opening center; `sillHeight` is the height above the floor
  - `style`: the type set by the user. Doors: `swingDoor`, `slidingDoor`, `foldingDoor`; windows: `casementWindow`, `slidingWindow`, `fixedWindow`, `awningWindow`. Missing means the user hasn't confirmed it
  - `hinge`: which side the hinges are on (`left` / `right`), as seen standing in the room facing the wall (i.e. looking toward `outward`)
  - `opensOutward`: whether a swing door opens away from the room; `false` or missing means it opens into the room
- `fixtures[]`: positions of toilets, sinks, stoves, washers, etc. They determine **drains, ventilation and electrical points** — do not move them casually
- `annotations[]`: user notes (`note`) and measurements (`measurement`); `photos` are photo paths
- `sitePhotos[]`: on-site photos (taken automatically while scanning, `isAuto: true`, or manually). Each has the camera's `cameraPosition`, `cameraDirection`, `cameraUp`, `verticalFov` (vertical field of view of the portrait image, degrees), and the `roomId` and `wallId` it shows.
  To see what a wall or room actually looks like (wall color, flooring, pipes, switches and outlets), check the matching photos.
  `build_whitebox.py` creates a camera for each photo (the Photo_Cameras collection) with the photo as its background, so you can overlay it on the whitebox

## Rooms

{{ROOM_TABLE}}

## User notes

{{ANNOTATIONS}}

## Tape-measured values

{{MEASURED}}

## Suggested workflow

1. In Blender run: `blender --background --python build_whitebox.py -- scene.json whitebox.blend`
   or import `whitebox.obj` directly
2. Read the notes above and look through `photos/` to understand the user's needs and the site
3. Design the interior in the whitebox (walls, floors, ceilings, cabinetry, furniture). **Do not move walls or door and window openings**
4. Plan bathrooms and kitchens around the positions in `fixtures`

## Known limitations

- LiDAR wall lengths are usually accurate to within a few centimeters; glass, mirrors and clutter increase the error
- Wall thickness is a default value (120 mm), not a measurement
- Walls with `isCurved: true` are curved walls approximated as straight lines
