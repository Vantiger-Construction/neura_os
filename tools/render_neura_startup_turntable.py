"""Render the owner's existing Lumen rig locally; Blender is build-time only.

blender -b -t 2 --python tools/render_neura_startup_turntable.py -- \
  --model /path/to/Meshy_AI_Lumen_Heart_biped_Character_output.fbx \
  --texture /path/to/Meshy_AI_Lumen_Heart_biped_texture_0.png \
  --output /path/to/frames

The source model/texture are intentionally not copied into the application.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--texture', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--frames', type=int, default=32)
    parser.add_argument('--width', type=int, default=160)
    parser.add_argument('--height', type=int, default=240)
    parser.add_argument('--cardinals-only', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    args.output.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(args.model.resolve()))
    armature = next(obj for obj in bpy.context.scene.objects if obj.type == 'ARMATURE')
    armature.animation_data_clear()
    for bone in armature.pose.bones:
        bone.rotation_mode = 'QUATERNION'
        bone.rotation_quaternion.identity()
        bone.location = (0, 0, 0)
        bone.scale = (1, 1, 1)
    for name, outward in [('LeftArm', 0.16), ('RightArm', -0.16)]:
        bone = armature.pose.bones[name]
        rest_direction = bone.bone.tail_local - bone.bone.head_local
        destination = Vector((outward, -0.035, -1)).normalized()
        adjustment = rest_direction.rotation_difference(destination)
        axes = bone.bone.matrix_local.to_quaternion()
        bone.rotation_quaternion = axes.inverted() @ adjustment @ axes
    bpy.context.view_layer.update()

    texture = bpy.data.images.load(str(args.texture.resolve()))
    for material in bpy.data.materials:
        material.use_nodes = True
        nodes = material.node_tree.nodes
        nodes.clear()
        output = nodes.new('ShaderNodeOutputMaterial')
        shader = nodes.new('ShaderNodeBsdfPrincipled')
        shader.inputs['Roughness'].default_value = 0.48
        shader.inputs['Metallic'].default_value = 0.16
        image = nodes.new('ShaderNodeTexImage')
        image.image = texture
        links = material.node_tree.links
        links.new(image.outputs['Color'], shader.inputs['Base Color'])
        links.new(image.outputs['Color'], shader.inputs['Emission Color'])
        shader.inputs['Emission Strength'].default_value = 0.10
        links.new(shader.outputs['BSDF'], output.inputs['Surface'])

    roots = [obj for obj in bpy.context.scene.objects if obj.parent is None]
    turntable = bpy.data.objects.new('NeuraStartupTurntable', None)
    bpy.context.collection.objects.link(turntable)
    for obj in roots:
        obj.parent = turntable

    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 48
    # CPU-only Blender distributions may omit OpenImageDenoise.
    scene.cycles.use_denoising = False
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 2
    scene.render.resolution_x = args.width
    scene.render.resolution_y = args.height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.color_depth = '8'
    scene.view_settings.view_transform = 'AgX'
    scene.world = bpy.data.worlds.new('Neutral studio')
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value = (0.18, 0.20, 0.28, 1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value = 0.35

    def aim(obj, target):
        obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()

    camera_data = bpy.data.cameras.new('Portrait camera')
    camera = bpy.data.objects.new('Portrait camera', camera_data)
    scene.collection.objects.link(camera)
    camera.location = (0, -4.5, 0.88)
    aim(camera, (0, 0, 0.86))
    camera_data.type = 'ORTHO'
    camera_data.ortho_scale = 1.88
    scene.camera = camera

    for name, location, color, power, size in [
        ('Soft key', (-2, -3, 3.8), (0.83, 0.90, 1.0), 380, 3),
        ('Warm fill', (2, -2, 2.2), (1.0, 0.82, 0.92), 230, 2.5),
        ('Violet rim', (0, 2, 3), (0.65, 0.55, 1.0), 430, 2),
    ]:
        light_data = bpy.data.lights.new(name, 'AREA')
        light_data.energy = power
        light_data.color = color
        light_data.shape = 'DISK'
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        scene.collection.objects.link(light)
        light.location = location
        aim(light, (0, 0, 0.9))

    indices = range(0, args.frames, args.frames // 4) if args.cardinals_only else range(args.frames)
    for index in indices:
        turntable.rotation_euler.z = 2 * math.pi * index / args.frames
        scene.render.filepath = str((args.output / f'frame_{index:02}.png').resolve())
        bpy.ops.render.render(write_still=True)

    inventory = {
        'source_model': args.model.name,
        'source_model_sha256': sha256(args.model),
        'source_texture': args.texture.name,
        'source_texture_sha256': sha256(args.texture),
        'blender_version': bpy.app.version_string,
        'frame_count': args.frames,
        'frame_width': args.width,
        'frame_height': args.height,
        'rendered_angles_degrees': [360 * i / args.frames for i in indices],
        'pose': 'arms resting at sides; original animation disabled',
        'runtime_3d_required': False,
    }
    (args.output / 'render-manifest.json').write_text(json.dumps(inventory, indent=2) + '\n')


if __name__ == '__main__':
    main()
