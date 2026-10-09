"""
根据 scene.json 在 Blender 里重建白模（带真实门窗洞口），按真实尺寸，单位米，Z 轴朝上。

用法：
  1. 命令行（无界面）：
     blender --background --python build_whitebox.py -- /path/to/scene.json [/path/to/output.blend]
  2. Blender 里：Scripting 面板打开本文件，点「运行脚本」。会读取和本脚本同目录的 scene.json；
     读不到时，把下面 SCENE_JSON 改成 scene.json 的完整路径。

生成的集合（Collection）：
  Walls            墙体（门窗位置已经挖空）
  Floors           每个房间的地面
  Ceilings         天花板（默认隐藏）
  Openings_Ref     门窗洞口的线框参考体（不渲染），自定义属性里有类型和尺寸
  Columns          柱子：手动标的柱子生成方柱；自动识别的贴墙柱已经包含在墙体里，只放一个带尺寸属性的标记
  Annotations      用户备注和测距（Empty 对象，自定义属性里有文字和照片路径）
  Photo_Cameras    每张现场照片对应一台相机（位置、朝向、视角和拍照时一致，照片设为相机背景）。
                   在视口里切到某台相机视角（小键盘 0），就能把白模和真实照片叠在一起对照
"""

import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

SCENE_JSON = ""  # 需要时手动填 scene.json 的完整路径


def resolve_paths():
    argv = sys.argv
    if "--" in argv:
        args = argv[argv.index("--") + 1:]
        if args:
            return args[0], (args[1] if len(args) > 1 else None)
    if SCENE_JSON:
        return SCENE_JSON, None
    candidates = []
    try:
        candidates.append(os.path.dirname(os.path.abspath(__file__)))
    except NameError:
        pass
    if bpy.data.filepath:
        candidates.append(os.path.dirname(bpy.data.filepath))
    for d in candidates:
        p = os.path.join(d, "scene.json")
        if os.path.exists(p):
            return p, None
    raise FileNotFoundError("找不到 scene.json，请在脚本顶部设置 SCENE_JSON")


def get_collection(name, hide_viewport=False, hide_render=False):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    col.hide_viewport = hide_viewport
    col.hide_render = hide_render
    return col


def get_material(name, rgba):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = rgba
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = 0.85
    return mat


def make_box(name, center, size, yaw, col, mat):
    cx, cy, cz = center
    sx, sy, sz = size
    c, s = math.cos(yaw), math.sin(yaw)
    verts = []
    for dz in (-0.5, 0.5):
        for dx, dy in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)):
            lx, ly = dx * sx, dy * sy
            verts.append((cx + lx * c - ly * s, cy + lx * s + ly * c, cz + dz * sz))
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mat)
    col.objects.link(obj)
    return obj


def make_slab(name, polygon, z, col, mat, facing_up=True):
    verts = [(p["x"], p["y"], z) for p in polygon]
    face = list(range(len(verts)))
    if not facing_up:
        face.reverse()
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], [face])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mat)
    col.objects.link(obj)
    return obj


def wall_pieces(length, height, openings):
    """与 App 里 WhiteboxBuilder.pieces 相同的算法：按洞口把墙切成实心块"""
    eps = 0.005
    spans = []
    for o in openings:
        a = max(0.0, o["centerOffset"] - o["width"] / 2)
        b = min(length, o["centerOffset"] + o["width"] / 2)
        z0 = max(0.0, o["sillHeight"])
        z1 = min(height, o["sillHeight"] + o["height"])
        if b - a > 0.01 and z1 - z0 > 0.01:
            spans.append((a, b, z0, z1))
    spans.sort()
    pieces = []
    cursor = 0.0
    for a, b, z0, z1 in spans:
        a = max(a, cursor)
        if a > cursor + eps:
            pieces.append((cursor, a, 0.0, height))
        if b > a + eps:
            if z0 > eps:
                pieces.append((a, b, 0.0, z0))
            if z1 < height - eps:
                pieces.append((a, b, z1, height))
        cursor = max(cursor, b)
    if cursor < length - eps:
        pieces.append((cursor, length, 0.0, height))
    return pieces


def end_extensions(wall, walls):
    """与 App 里 WhiteboxBuilder.endExtensions 相同：外转角处把墙延长对方的墙厚，补上缺角"""
    def ext(px, py):
        best = 0.0
        for other in walls:
            if other["id"] == wall["id"] or other["length"] <= 0.001:
                continue
            osx, osy = other["start"]["x"], other["start"]["y"]
            oex, oey = other["end"]["x"], other["end"]["y"]
            odx, ody = (oex - osx) / other["length"], (oey - osy) / other["length"]
            if math.hypot(osx - px, osy - py) < 0.2:
                ax, ay = odx, ody
            elif math.hypot(oex - px, oey - py) < 0.2:
                ax, ay = -odx, -ody
            else:
                continue
            if ax * wall["outward"]["x"] + ay * wall["outward"]["y"] < -0.5:
                best = max(best, other["thickness"])
        return best

    return ext(wall["start"]["x"], wall["start"]["y"]), ext(wall["end"]["x"], wall["end"]["y"])


def build_photo_cameras(data, base_dir):
    """每张现场照片还原一台同位置、同角度、同视角的相机，并把照片设为相机背景（视口里从相机视角看即可对照）"""
    photos = data.get("sitePhotos", [])
    if not photos:
        return
    col = get_collection("Photo_Cameras", hide_render=True)
    for ph in photos:
        cam_data = bpy.data.cameras.new(f"Cam_{ph['id']}")
        cam_data.sensor_fit = "VERTICAL"
        cam_data.angle = math.radians(ph["verticalFov"])
        cam_data.clip_start = 0.05
        cam = bpy.data.objects.new(f"Photo_{ph['id']}", cam_data)

        # Blender 相机看向本地 -Z，本地 +Y 是画面上方
        f = Vector((ph["cameraDirection"]["x"], ph["cameraDirection"]["y"], ph["cameraDirection"]["z"])).normalized()
        u = Vector((ph["cameraUp"]["x"], ph["cameraUp"]["y"], ph["cameraUp"]["z"]))
        u = (u - f * u.dot(f)).normalized()
        z_axis = -f
        x_axis = u.cross(z_axis)
        rot = Matrix((x_axis, u, z_axis)).transposed()
        cam.matrix_world = Matrix.Translation(Vector((ph["cameraPosition"]["x"], ph["cameraPosition"]["y"],
                                                      ph["cameraPosition"]["z"]))) @ rot.to_4x4()

        cam["photo"] = ph["path"]
        cam["room"] = ph.get("roomId") or ""
        cam["wall"] = ph.get("wallId") or ""
        cam["auto"] = bool(ph.get("isAuto"))

        img_path = os.path.join(base_dir, ph["path"])
        if os.path.exists(img_path):
            bg = cam_data.background_images.new()
            bg.image = bpy.data.images.load(img_path, check_existing=True)
            bg.alpha = 0.6
            cam_data.show_background_images = True
        col.objects.link(cam)


def build(scene_path):
    with open(scene_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.length_unit = "METERS"

    walls_col = get_collection("Walls")
    floors_col = get_collection("Floors")
    ceilings_col = get_collection("Ceilings", hide_viewport=True, hide_render=True)
    openings_col = get_collection("Openings_Ref", hide_render=True)
    columns_col = get_collection("Columns")
    notes_col = get_collection("Annotations", hide_render=True)

    wall_mat = get_material("Whitebox_Wall", (0.95, 0.95, 0.95, 1))
    floor_mat = get_material("Whitebox_Floor", (0.8, 0.8, 0.8, 1))
    ceiling_mat = get_material("Whitebox_Ceiling", (0.98, 0.98, 0.98, 1))
    ref_mat = get_material("Reference", (0.4, 0.7, 0.75, 1))

    rooms = {r["id"]: r for r in data["rooms"]}

    for room in data["rooms"]:
        if len(room["floorPolygon"]) < 3:
            continue
        floor = make_slab(f"Floor_{room['id']}_{room['name']}", room["floorPolygon"], 0.0, floors_col, floor_mat)
        floor["room_name"] = room["name"]
        floor["area_m2"] = round(room["area"], 2)
        make_slab(f"Ceiling_{room['id']}_{room['name']}", room["floorPolygon"], room["height"],
                  ceilings_col, ceiling_mat, facing_up=False)

    for wall in data["walls"]:
        sx, sy = wall["start"]["x"], wall["start"]["y"]
        ex, ey = wall["end"]["x"], wall["end"]["y"]
        length = wall["length"]
        if length <= 0.001:
            continue
        dx, dy = (ex - sx) / length, (ey - sy) / length
        yaw = math.atan2(dy, dx)
        t = wall["thickness"]
        ox, oy = wall["outward"]["x"] * t / 2, wall["outward"]["y"] * t / 2
        wall_openings = [o for o in data["openings"] if o["wallId"] == wall["id"]]
        room_names = ",".join(rooms[r]["name"] for r in wall["roomIds"] if r in rooms)

        ext_start, ext_end = end_extensions(wall, data["walls"])
        for i, (u0, u1, z0, z1) in enumerate(wall_pieces(length, wall["height"], wall_openings)):
            if u0 <= 0.001:
                u0 = -ext_start
            if u1 >= length - 0.001:
                u1 = length + ext_end
            u = (u0 + u1) / 2
            obj = make_box(f"Wall_{wall['id']}_{i + 1}",
                           (sx + dx * u + ox, sy + dy * u + oy, (z0 + z1) / 2),
                           (u1 - u0, t, z1 - z0), yaw, walls_col, wall_mat)
            obj["wall_id"] = wall["id"]
            obj["rooms"] = room_names
            obj["wall_length_mm"] = round(length * 1000)
            if wall.get("measuredLength"):
                obj["measured_length_mm"] = round(wall["measuredLength"] * 1000)

        for o in wall_openings:
            u = o["centerOffset"]
            obj = make_box(f"{o['kind'].capitalize()}_{o['id']}",
                           (sx + dx * u + ox, sy + dy * u + oy, o["sillHeight"] + o["height"] / 2),
                           (o["width"], t + 0.04, o["height"]), yaw, openings_col, ref_mat)
            obj.display_type = "WIRE"
            obj["kind"] = o["kind"]
            obj["width_mm"] = round(o["width"] * 1000)
            obj["height_mm"] = round(o["height"] * 1000)
            obj["sill_mm"] = round(o["sillHeight"] * 1000)
            obj["style"] = o.get("style") or "unknown"
            if o.get("hinge"):
                obj["hinge"] = o["hinge"]
            if o.get("opensOutward") is not None:
                obj["opens_outward"] = bool(o["opensOutward"])

    for col in data.get("columns", []):
        c = col["center"]
        if col.get("wallIds"):
            # 已经由墙体组成，只放一个标记
            obj = bpy.data.objects.new(f"Column_{col['id']}", None)
            obj.empty_display_type = "CUBE"
            obj.empty_display_size = 0.5
            obj.location = (c["x"], c["y"], col["height"] / 2)
            obj.scale = (col["width"], col["depth"], col["height"])
            obj.rotation_euler = (0, 0, col["yaw"])
            columns_col.objects.link(obj)
        else:
            obj = make_box(f"Column_{col['id']}", (c["x"], c["y"], col["height"] / 2),
                           (col["width"], col["depth"], col["height"]), col["yaw"], columns_col, wall_mat)
        obj["kind"] = col["kind"]
        obj["width_mm"] = round(col["width"] * 1000)
        obj["depth_mm"] = round(col["depth"] * 1000)
        obj["source"] = col.get("source", "")

    for a in data.get("annotations", []):
        p = a["position"]
        empty = bpy.data.objects.new(f"Note_{a['number']}" if a["kind"] == "note" else f"Measure_{a['number']}", None)
        empty.empty_display_type = "SPHERE" if a["kind"] == "note" else "PLAIN_AXES"
        empty.empty_display_size = 0.1
        empty.location = (p["x"], p["y"], p["z"])
        empty["text"] = a.get("text", "")
        empty["photos"] = ",".join(a.get("photos", []))
        if a.get("distance"):
            empty["distance_mm"] = round(a["distance"] * 1000)
        notes_col.objects.link(empty)

    build_photo_cameras(data, os.path.dirname(os.path.abspath(scene_path)))

    print(f"白模重建完成：{len(data['rooms'])} 个房间，{len(data['walls'])} 面墙，{len(data['openings'])} 个门窗洞口")


if __name__ == "__main__":
    scene_path, out_path = resolve_paths()
    build(scene_path)
    if out_path:
        bpy.ops.wm.save_as_mainfile(filepath=out_path)
        print(f"已保存：{out_path}")
