# Recette H12, côté outil de contrôle. À lancer après test/host/h12.rb :
#   blender --background --factory-startup --python test/host/h12_blender.py
# Réglage d'import : axes Y avant et Z haut (l'export ne permute pas), échelle 1 pour un document
# en mètres. Écrit tmp/h12/blender.txt et une vue par style. Le dernier mot du rapport est « FIN ».
import json
import os
import traceback

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(REPO, "tmp", "h12")
REPORT = os.path.join(OUT, "blender.txt")
DIMENSION_TOLERANCE = 0.01  # H12 : écart <= 1 %
PLANE_TOLERANCE_M = 0.001
AREA_TOLERANCE = 0.01
COLOR_TOLERANCE = 0.01
RAY_MARGIN_M = 0.05

lines = []
failures = 0


def log(text):
    lines.append(text)
    with open(REPORT, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def check(label, ok, detail=""):
    global failures
    if not ok:
        failures += 1
    log(f"{'OK   ' if ok else 'ECHEC'} {label}{' : ' + str(detail) if detail != '' else ''}")


def near(label, expected, actual, tolerance=DIMENSION_TOLERANCE):
    gap = abs(actual - expected) / abs(expected)
    check(label, gap <= tolerance, f"attendu {expected:.3f}, lu {actual:.3f}, écart {gap * 100:.3f} %")


def import_obj(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=path, forward_axis="Y", up_axis="Z", global_scale=1.0)
    return [o for o in bpy.data.objects if o.type == "MESH"]


def world_mesh(objects):
    """Tous les polygones en coordonnées du monde, avec leur matériau."""
    points = []
    polygons = []
    records = []
    for obj in objects:
        offset = len(points)
        points.extend(obj.matrix_world @ v.co for v in obj.data.vertices)
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        for poly in obj.data.polygons:
            indices = [offset + i for i in poly.vertices]
            polygons.append(indices)
            slot = obj.data.materials[poly.material_index] if obj.data.materials else None
            records.append(
                {
                    "points": [points[i] for i in indices],
                    "normal": (normal_matrix @ poly.normal).normalized(),
                    "area": poly.area,
                    "material": slot.name if slot else "",
                }
            )
    return points, polygons, records


def on_plane(record, axis, value):
    return all(abs(p[axis] - value) <= PLANE_TOLERANCE_M for p in record["points"])


def parse_mtl(path):
    colors = {}
    current = None
    with open(path, encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            parts = raw.split()
            if not parts:
                continue
            if parts[0] == "newmtl":
                current = " ".join(parts[1:])
            elif parts[0] == "Kd" and current:
                colors[current] = [float(x) for x in parts[1:4]]
    return colors


def simplify(text):
    """L'exporteur OBJ remplace espaces et accents par _ : seuls les caractères ASCII sont comparés."""
    return "".join(c.lower() for c in text if c.isascii() and c.isalnum())


def control_materials(entry, base):
    mtl = os.path.join(OUT, base + ".mtl")
    check(f"{base} : fichier de matériaux présent", os.path.exists(mtl))
    colors = parse_mtl(mtl) if os.path.exists(mtl) else {}
    log(f"MESURE {base} : matériaux lus {sorted(colors)}, dans Blender {sorted(m.name for m in bpy.data.materials)}")
    for expected in entry["materials"]:
        wanted = simplify("ARCHGEN " + expected["label"])
        found = [name for name in colors if simplify(name) == wanted]
        check(f"{base} : matériau {expected['label']} nommé", bool(found), sorted(colors))
        if not found:
            continue
        hexa = expected["srgb"].lstrip("#")
        target = [int(hexa[i : i + 2], 16) / 255.0 for i in (0, 2, 4)]
        gap = max(abs(a - b) for a, b in zip(colors[found[0]], target))
        check(f"{base} : couleur {expected['label']}", gap <= COLOR_TOLERANCE, f"écart {gap:.4f}")


def control_normals(entry, base, records):
    width, depth = entry["width_m"], entry["depth_m"]
    planes = {"front": (1, 0.0, -1), "right": (0, width, 1), "rear": (1, depth, 1), "left": (0, 0.0, -1)}
    for facade, (axis, value, sign) in planes.items():
        faces = [r for r in records if on_plane(r, axis, value)]
        outward = [r for r in faces if r["normal"][axis] * sign > 0.99]
        check(f"{base} : {facade} orientée vers l'extérieur", bool(faces) and len(outward) == len(faces), f"{len(outward)}/{len(faces)} polygones")
        wanted = entry["wall_areas"].get(facade)
        if wanted:
            near(f"{base} : aire du mur {facade}, baies déduites", wanted, sum(r["area"] for r in faces), AREA_TOLERANCE)
    # Par le centre du polygone : le haut d'un mur touche aussi le sommet d'un toit plat.
    top = max(records, key=lambda r: sum(p[2] for p in r["points"]) / len(r["points"]))
    check(f"{base} : le polygone le plus haut regarde vers le haut", top["normal"][2] > 0, f"nz {top['normal'][2]:.3f}")
    up = sum(r["area"] for r in records if r["normal"][2] > 0.01)
    down = sum(r["area"] for r in records if r["normal"][2] < -0.01)
    log(f"MESURE {base} : aire vers le haut {up:.2f} m², vers le bas {down:.2f} m²")


def control_dimensions(entry, base, points, records):
    mins = [min(p[i] for p in points) for i in range(3)]
    maxs = [max(p[i] for p in points) for i in range(3)]
    log(f"MESURE {base} : boîte {[round(v, 4) for v in mins]} à {[round(v, 4) for v in maxs]}")
    bounds = entry["bounds"]
    for i, axis in enumerate("XYZ"):
        near(f"{base} : étendue {axis}", bounds["max"][i] - bounds["min"][i], maxs[i] - mins[i])
    walls_y = [r for r in records if on_plane(r, 1, 0.0)]
    walls_x = [r for r in records if on_plane(r, 0, entry["width_m"])]
    width = max(p[0] for r in walls_y for p in r["points"]) - min(p[0] for r in walls_y for p in r["points"])
    depth = max(p[1] for r in walls_x for p in r["points"]) - min(p[1] for r in walls_x for p in r["points"])
    near(f"{base} : W sur le mur avant", entry["width_m"], width)
    near(f"{base} : D sur le mur droit", entry["depth_m"], depth)
    near(f"{base} : H-toit", entry["roof_top_z_m"], maxs[2])


def segment_hits(tree, item, wall_m):
    point = Vector(item["point"])
    normal = Vector(item["normal"])
    start = point + normal * RAY_MARGIN_M
    length = 2 * RAY_MARGIN_M + wall_m
    hit, _, _, _ = tree.ray_cast(start, -normal, length)
    return hit is not None


def control_openings(entry, base, points, polygons):
    tree = BVHTree.FromPolygons([tuple(p) for p in points], polygons, all_triangles=False, epsilon=0.0)
    blocked = [o["id"] for o in entry["openings"] if segment_hits(tree, o, entry["wall_m"])]
    check(f"{base} : {len(entry['openings'])} baies traversantes", not blocked, blocked[:5] if blocked else "")
    solid = [w["id"] for w in entry["witnesses"] if segment_hits(tree, w, entry["wall_m"])]
    check(f"{base} : témoins pleins arrêtés", len(solid) == len(entry["witnesses"]), solid)


def render_view(base, objects):
    """Vue de contrôle : un échec n'invalide pas les mesures, il est seulement signalé."""
    try:
        scene = bpy.context.scene
        scene.render.engine = "BLENDER_WORKBENCH"
        scene.display.shading.color_type = "MATERIAL"
        scene.display.shading.show_backface_culling = True
        scene.render.resolution_x, scene.render.resolution_y = 900, 700
        scene.render.filepath = os.path.join(OUT, base + ".png")
        camera = bpy.data.objects.new("controle", bpy.data.cameras.new("controle"))
        scene.collection.objects.link(camera)
        camera.data.lens = 35
        camera.rotation_euler = (1.25, 0.0, 0.55)
        scene.camera = camera
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.update()
        corners = [obj.matrix_world @ Vector(c) for obj in objects for c in obj.bound_box]
        coordinates = [c for corner in corners for c in corner]
        depsgraph = bpy.context.evaluated_depsgraph_get()
        location, _ = camera.camera_fit_coords(depsgraph, coordinates)
        camera.location = location
        bpy.ops.render.render(write_still=True)
        log(f"VUE {base} : {scene.render.filepath}")
    except Exception as error:  # noqa: BLE001
        log(f"VUE {base} non produite : {error}")


def main():
    log(f"H12 Blender {bpy.app.version_string}, import OBJ axes Y/Z, échelle 1")
    with open(os.path.join(OUT, "expected.json"), encoding="utf-8") as handle:
        fixtures = json.load(handle)["fixtures"]
    for entry in fixtures:
        base = entry["file"].rsplit(".", 1)[0]
        objects = import_obj(os.path.join(OUT, entry["file"]))
        check(f"{base} : importé", bool(objects), f"{len(objects)} objets")
        points, polygons, records = world_mesh(objects)
        log(f"MESURE {base} : {len(records)} polygones, {len(points)} sommets")
        control_dimensions(entry, base, points, records)
        control_normals(entry, base, records)
        control_openings(entry, base, points, polygons)
        control_materials(entry, base)
        render_view(base, objects)


try:
    main()
except Exception:  # noqa: BLE001
    failures += 1
    log("ECHEC exception\n" + traceback.format_exc())
log(f"FIN {failures} echec(s)")
