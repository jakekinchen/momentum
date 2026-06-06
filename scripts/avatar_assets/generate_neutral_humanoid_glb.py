#!/usr/bin/env python3
"""Generate CamiFit's neutral avatar guide mannequin as a GLB asset.

Run with Blender:
  blender --background --python scripts/avatar_assets/generate_neutral_humanoid_glb.py
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "Sources" / "CamiFitApp" / "Resources" / "Avatars" / "neutral_humanoid.glb"


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def make_material(name: str, color: tuple[float, float, float, float], roughness: float = 0.82):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = 0.02
    return material


def make_sphere(name: str, material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1.0, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    obj.data.name = f"{name}.mesh"
    obj.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    return obj


def make_capsule_mesh(name: str, material, segments: int = 32, hemisphere_rings: int = 8) -> bpy.types.Object:
    radius = 0.18
    cylinder_half_height = 0.32
    rings: list[tuple[float, float]] = []

    for index in range(hemisphere_rings + 1):
        phi = (index / hemisphere_rings) * (math.pi / 2)
        rings.append((cylinder_half_height + radius * math.cos(phi), radius * math.sin(phi)))

    rings.append((-cylinder_half_height, radius))

    for index in range(1, hemisphere_rings + 1):
        phi = (math.pi / 2) + (index / hemisphere_rings) * (math.pi / 2)
        rings.append((-cylinder_half_height + radius * math.cos(phi), radius * math.sin(phi)))

    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int, int]] = []
    for z, ring_radius in rings:
        for segment in range(segments):
            angle = (segment / segments) * (math.pi * 2)
            vertices.append((ring_radius * math.cos(angle), ring_radius * math.sin(angle), z))

    for ring_index in range(len(rings) - 1):
        ring_start = ring_index * segments
        next_start = (ring_index + 1) * segments
        for segment in range(segments):
            faces.append((
                ring_start + segment,
                ring_start + ((segment + 1) % segments),
                next_start + ((segment + 1) % segments),
                next_start + segment,
            ))

    mesh = bpy.data.meshes.new(f"{name}.mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    obj.select_set(False)
    return obj


def make_shoe_mesh(name: str, material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    obj.data.name = f"{name}.mesh"
    obj.data.materials.append(material)

    bevel = obj.modifiers.new("softened edges", "BEVEL")
    bevel.width = 0.16
    bevel.segments = 6
    bevel.affect = "EDGES"
    obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def build_asset() -> None:
    clear_scene()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    root = bpy.data.objects.new("avatar.root", None)
    bpy.context.collection.objects.link(root)

    torso = make_material("warm porcelain body", (0.86, 0.93, 0.92, 1.0))
    limb = make_material("soft training suit", (0.93, 0.98, 0.96, 1.0))
    far_limb = make_material("recessed far side", (0.62, 0.74, 0.73, 1.0))
    accent = make_material("aqua guide accent", (0.78, 0.96, 0.93, 1.0))

    sphere_nodes = {
        "avatar.head": accent,
        "avatar.chest": torso,
        "avatar.abdomen": torso,
        "avatar.pelvis": torso,
        "avatar.near.hand": limb,
        "avatar.far.hand": far_limb,
        "avatar.near.elbow": limb,
        "avatar.far.elbow": far_limb,
        "avatar.near.knee": limb,
        "avatar.far.knee": far_limb,
        "avatar.near.ankle": limb,
        "avatar.far.ankle": far_limb,
    }
    capsule_nodes = {
        "avatar.neck": torso,
        "avatar.spine": torso,
        "avatar.shoulderBridge": torso,
        "avatar.hipBridge": torso,
        "avatar.near.upperArm": limb,
        "avatar.near.forearm": limb,
        "avatar.far.upperArm": far_limb,
        "avatar.far.forearm": far_limb,
        "avatar.near.upperLeg": limb,
        "avatar.near.lowerLeg": limb,
        "avatar.far.upperLeg": far_limb,
        "avatar.far.lowerLeg": far_limb,
    }
    shoe_nodes = {
        "avatar.near.foot": accent,
        "avatar.far.foot": far_limb,
    }

    objects: list[bpy.types.Object] = []
    for name, material in sphere_nodes.items():
        objects.append(make_sphere(name, material))
    for name, material in capsule_nodes.items():
        objects.append(make_capsule_mesh(name, material))
    for name, material in shoe_nodes.items():
        objects.append(make_shoe_mesh(name, material))

    for obj in objects:
        obj.parent = root
        obj.location = (0, 0, 0)
        obj.rotation_euler = (0, 0, 0)
        obj.scale = (1, 1, 1)

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root

    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
        export_yup=True,
    )
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    build_asset()
