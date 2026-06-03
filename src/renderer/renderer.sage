# -----------------------------------------
# renderer.sage - SageMusic GPU Rendering Engine
# Retained-Mode Scene Graph using Vulkan/OpenGL
# -----------------------------------------

import gpu
import io
import json
import graphics.math3d as math3d
import graphics.renderer as base_renderer
from graphics.mesh import mesh_vertex_binding, mesh_vertex_attribs
from layout.layout import pitch_to_y, get_measure_layout_pos

# ============================================================================
# Glyph Mapping (SMuFL snippets)
# ============================================================================
# In a real app, these would be UV coordinates in a loaded texture atlas.
# For this prototype, we'll define a few key symbols.
let SMUFL = {
    "g_clef": 0xE050,
    "f_clef": 0xE062,
    "c_clef": 0xE05C,
    "notehead_whole": 0xE0A2,
    "notehead_half": 0xE0A3,
    "notehead_quarter": 0xE0A4,
    "rest_whole": 0xE4E3,
    "rest_half": 0xE4E4,
    "rest_quarter": 0xE4E5,
    "rest_eighth": 0xE4E6,
    "sharp": 0xE262,
    "flat": 0xE260,
    "natural": 0xE261,
    "time_4": 0xE084
}

# Helper to prevent path traversal
proc sanitize_path(path):
    if path == nil or len(path) == 0:
        return ""
    if path[0] == "/":
        return "" # No absolute paths
    let i = 0
    while i < len(path) - 1:
        if path[i] == "." and path[i+1] == ".":
            return "" # No traversal
        i = i + 1
    return path

# ============================================================================
# Render Context
# ============================================================================
class MusicRenderer:
    proc init(self, width, height):
        self.base = base_renderer.create_renderer(width, height, "SageMusic")
        self.width = width
        self.height = height
        self.zoom = 1.0
        self.offset_x = 0.0
        self.offset_y = 0.0
        self.preview_info = nil

        # Load Atlas Metadata JSON
        let atlas_path = sanitize_path("assets/bravura_atlas.json")
        if io.exists(atlas_path):
            let meta_str = io.readfile(atlas_path)
            let root = json.cJSON_Parse(meta_str)
            if root != nil:
                self.atlas_data = json.cJSON_ToSage(root)
                json.cJSON_Delete(root)
            else:
                self.atlas_data = nil
        else:
            self.atlas_data = nil
        
        # Shader constants (Projection Matrix)
        self.proj = math3d.mat4_ortho(0, width, 0, height, -1, 1)
        
        # Shaders (Reusing pre-compiled shader modules)
        # SEC-FS-7: Fixed path traversal by making paths local to project
        let vert_path = sanitize_path("assets/shaders/cube.vert.spv")
        let frag_path = sanitize_path("assets/shaders/text3d.frag.spv")
        
        let vert = -1
        let frag = -1
        if io.exists(vert_path) and io.exists(frag_path):
            vert = gpu.load_shader(vert_path, gpu.STAGE_VERTEX)
            frag = gpu.load_shader(frag_path, gpu.STAGE_FRAGMENT)

        if vert < 0 or frag < 0:
            # Fallback to local sprite shaders if common shaders are missing
            vert = gpu.load_shader(sanitize_path("src/renderer/sprite.vert.spv"), gpu.STAGE_VERTEX)
            frag = gpu.load_shader(sanitize_path("src/renderer/sprite.frag.spv"), gpu.STAGE_FRAGMENT)
            
            if vert < 0 or frag < 0:
                print "Error: Failed to load primitive shaders. Please ensure assets/shaders or src/renderer contains valid SPV files."
                return

        # Pipeline Layout (64-byte push constant for projection matrix)
        self.pipe_layout = gpu.create_pipeline_layout([], 64, gpu.STAGE_VERTEX)
        if self.pipe_layout < 0:
            print "Error: Failed to create pipeline layout"
            return

        # Line Pipeline (Staff lines, stems, measure barlines)
        let line_cfg = {}
        line_cfg["layout"] = self.pipe_layout
        line_cfg["render_pass"] = self.base["render_pass"]
        line_cfg["vertex_shader"] = vert
        line_cfg["fragment_shader"] = frag
        line_cfg["topology"] = gpu.TOPO_LINE_LIST
        line_cfg["cull_mode"] = gpu.CULL_NONE
        line_cfg["front_face"] = gpu.FRONT_CCW
        line_cfg["depth_test"] = false
        line_cfg["depth_write"] = false
        line_cfg["blend"] = true
        line_cfg["vertex_bindings"] = [mesh_vertex_binding()]
        line_cfg["vertex_attribs"] = mesh_vertex_attribs()
        self.line_pipeline = gpu.create_graphics_pipeline(line_cfg)
        if self.line_pipeline < 0:
            raise "Failed to create line pipeline"

        # Rect Pipeline (Noteheads, rests background, UI elements)
        let rect_cfg = {}
        rect_cfg["layout"] = self.pipe_layout
        rect_cfg["render_pass"] = self.base["render_pass"]
        rect_cfg["vertex_shader"] = vert
        rect_cfg["fragment_shader"] = frag
        rect_cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
        rect_cfg["cull_mode"] = gpu.CULL_NONE
        rect_cfg["front_face"] = gpu.FRONT_CCW
        rect_cfg["depth_test"] = false
        rect_cfg["depth_write"] = false
        rect_cfg["blend"] = true
        rect_cfg["vertex_bindings"] = [mesh_vertex_binding()]
        rect_cfg["vertex_attribs"] = mesh_vertex_attribs()
        self.rect_pipeline = gpu.create_graphics_pipeline(rect_cfg)
        if self.rect_pipeline < 0:
            raise "Failed to create rect pipeline"

        # Pipeline for glyphs (texture mapped quads)
        self.glyph_pipeline = self.create_glyph_pipeline()

        # Dynamic Resource Tracking for frames in flight
        self.frame_resources = [[], []]
        self.cf = 0
        
        # Batching buffers
        self.line_vertices = []
        self.rect_vertices = []
        self.glyph_vertices = []
        self.font_vertices = []

    proc create_glyph_pipeline(self):
        # 1. Create Descriptor Set Layout
        let b0 = {}
        b0["binding"] = 0
        b0["type"] = gpu.DESC_COMBINED_SAMPLER
        b0["stage"] = gpu.STAGE_FRAGMENT
        b0["count"] = 1
        self.sprite_desc_layout = gpu.create_descriptor_layout([b0])
        
        # 2. Create Descriptor Pool for 2 descriptor sets
        let ps = {}
        ps["type"] = gpu.DESC_COMBINED_SAMPLER
        ps["count"] = 2
        self.sprite_desc_pool = gpu.create_descriptor_pool(2, [ps])
        self.sprite_desc_set = gpu.allocate_descriptor_set(self.sprite_desc_pool, self.sprite_desc_layout)
        
        # 3. Load Sprite Texture & Sampler
        let sprite_path = sanitize_path("assets/bravura_atlas.png")
        if io.exists(sprite_path):
            self.sprite_texture = gpu.load_texture(sprite_path)
        else:
            self.sprite_texture = -1

        self.sprite_sampler = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_CLAMP_EDGE)
        if self.sprite_texture >= 0:
            gpu.update_descriptor_image(self.sprite_desc_set, 0, self.sprite_texture, self.sprite_sampler)
        
        # 3.1 Load UI Font (Lato)
        let font_path = sanitize_path("assets/lato.ttf")
        if io.exists(font_path):
            self.ui_font = gpu.load_font(font_path, 16)
            let f_atlas = gpu.font_atlas(self.ui_font)
            let f_tex_path = sanitize_path(f_atlas["path"])
            let f_tex = -1
            if io.exists(f_tex_path):
                f_tex = gpu.load_texture(f_tex_path)
            
            let f_smp = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_CLAMP_EDGE)
            if f_tex >= 0:
                gpu.font_set_atlas(self.ui_font, f_tex, f_smp)
                self.font_desc_set = gpu.allocate_descriptor_set(self.sprite_desc_pool, self.sprite_desc_layout)
                gpu.update_descriptor_image(self.font_desc_set, 0, f_tex, f_smp)
            else:
                self.font_desc_set = -1
        else:
            self.ui_font = nil
            self.font_desc_set = -1
            
        # 4. Pipeline Layout (64-byte projection matrix + 1 descriptor set)
        self.sprite_pipe_layout = gpu.create_pipeline_layout([self.sprite_desc_layout], 64, gpu.STAGE_VERTEX)
        
        # 5. Load Compiled Shaders
        let s_vert_path = sanitize_path("src/renderer/sprite.vert.spv")
        let s_frag_path = sanitize_path("src/renderer/sprite.frag.spv")
        let f_frag_path = sanitize_path("src/renderer/font.frag.spv")
        
        let vert_shader = -1
        let frag_shader = -1
        let font_frag_shader = -1
        
        if io.exists(s_vert_path) and io.exists(s_frag_path) and io.exists(f_frag_path):
            vert_shader = gpu.load_shader(s_vert_path, gpu.STAGE_VERTEX)
            frag_shader = gpu.load_shader(s_frag_path, gpu.STAGE_FRAGMENT)
            font_frag_shader = gpu.load_shader(f_frag_path, gpu.STAGE_FRAGMENT)

        if vert_shader < 0 or frag_shader < 0 or font_frag_shader < 0:
            print "Error: Failed to load sprite or font shaders"
            return -1
        
        # 6. Graphics Pipeline Setup
        let s_vb = {}
        s_vb["binding"] = 0
        s_vb["stride"] = 32
        s_vb["rate"] = gpu.INPUT_RATE_VERTEX
        
        let s_va0 = {}
        s_va0["location"] = 0
        s_va0["binding"] = 0
        s_va0["format"] = gpu.ATTR_VEC2
        s_va0["offset"] = 0
        
        let s_va1 = {}
        s_va1["location"] = 1
        s_va1["binding"] = 0
        s_va1["format"] = gpu.ATTR_VEC2
        s_va1["offset"] = 8
        
        let s_va2 = {}
        s_va2["location"] = 2
        s_va2["binding"] = 0
        s_va2["format"] = gpu.ATTR_VEC4
        s_va2["offset"] = 16
        
        let s_cfg = {}
        s_cfg["layout"] = self.sprite_pipe_layout
        s_cfg["render_pass"] = self.base["render_pass"]
        s_cfg["vertex_shader"] = vert_shader
        s_cfg["fragment_shader"] = frag_shader
        s_cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
        s_cfg["cull_mode"] = gpu.CULL_NONE
        s_cfg["front_face"] = gpu.FRONT_CCW
        s_cfg["depth_test"] = false
        s_cfg["depth_write"] = false
        s_cfg["blend"] = true
        s_cfg["vertex_bindings"] = [s_vb]
        s_cfg["vertex_attribs"] = [s_va0, s_va1, s_va2]
        
        let pipeline = gpu.create_graphics_pipeline(s_cfg)
        if pipeline < 0:
            print "Error: Failed to create glyph pipeline"
            return -1
            
        # Create font pipeline
        s_cfg["fragment_shader"] = font_frag_shader
        self.font_pipeline = gpu.create_graphics_pipeline(s_cfg)
        if self.font_pipeline < 0:
            print "Error: Failed to create font pipeline"
            return -1
            
        return pipeline

    proc begin_frame(self):
        let frame_info = base_renderer.begin_frame(self.base)
        if frame_info == nil:
            return nil
        
        let cf = frame_info["current_frame"]
        let res_list = self.frame_resources[cf]
        let r_idx = 0
        while r_idx < len(res_list):
            gpu.destroy_buffer(res_list[r_idx])
            r_idx = r_idx + 1
        self.frame_resources[cf] = []
        
        return frame_info

    proc end_frame(self, frame_info):
        base_renderer.end_frame(self.base, frame_info)

    proc recreate_swapchain(self):
        gpu.device_wait_idle()
        
        let r = self.base
        let i = 0
        while i < len(r["framebuffers"]):
            gpu.destroy_framebuffer(r["framebuffers"][i])
            i = i + 1

        gpu.destroy_image(r["depth_image"])

        let ok = gpu.recreate_swapchain()
        if ok == false:
            return false

        let ext = gpu.swapchain_extent()
        let w = ext["width"]
        let h = ext["height"]
        r["width"] = w
        r["height"] = h

        let depth = gpu.create_depth_buffer(w, h)
        r["depth_image"] = depth

        let framebuffers = gpu.create_swapchain_framebuffers_depth(r["render_pass"], depth)
        r["framebuffers"] = framebuffers

        self.proj = math3d.mat4_ortho(0, w, 0, h, -1, 1)
        return true

    proc draw_score(self, frame_info, score, view_mode):
        self.cf = frame_info["current_frame"]
        let cmd = frame_info["cmd"]
        
        # Reset batches
        self.line_vertices = []
        self.rect_vertices = []
        self.glyph_vertices = []
        self.font_vertices = []
        
        # Draw Paper White background covering the screen (to the right of sidebar)
        self.draw_rect(cmd, 250.0, 0.0, self.base["width"] - 250.0, self.base["height"], [0.98, 0.98, 0.96, 1.0])
        
        # Iterate through parts, systems, and measures
        let part_idx = 0
        while part_idx < len(score.parts):
            let part = score.parts[part_idx]
            self.draw_part(cmd, part, part_idx, score, view_mode)
            part_idx = part_idx + 1

        if self.preview_info != nil:
            let pr = self.preview_info
            self.draw_note_preview(cmd, pr["x"], pr["y"], pr["duration"])
            
        # Flush all batches
        self.flush_batches(cmd)

    proc flush_batches(self, cmd):
        # 1. Flush Lines
        if len(self.line_vertices) > 0:
            let vbuf = gpu.upload_device_local(self.line_vertices, gpu.BUFFER_VERTEX)
            push(self.frame_resources[self.cf], vbuf)
            gpu.cmd_bind_graphics_pipeline(cmd, self.line_pipeline)
            gpu.cmd_push_constants(cmd, self.pipe_layout, gpu.STAGE_VERTEX, self.proj)
            gpu.cmd_bind_vertex_buffer(cmd, vbuf)
            gpu.cmd_draw(cmd, len(self.line_vertices) / 8, 1, 0, 0)
            
        # 2. Flush Rects
        if len(self.rect_vertices) > 0:
            let vbuf = gpu.upload_device_local(self.rect_vertices, gpu.BUFFER_VERTEX)
            push(self.frame_resources[self.cf], vbuf)
            gpu.cmd_bind_graphics_pipeline(cmd, self.rect_pipeline)
            gpu.cmd_push_constants(cmd, self.pipe_layout, gpu.STAGE_VERTEX, self.proj)
            gpu.cmd_bind_vertex_buffer(cmd, vbuf)
            gpu.cmd_draw(cmd, len(self.rect_vertices) / 8, 1, 0, 0)
            
        # 3. Flush Glyphs
        if len(self.glyph_vertices) > 0:
            let vbuf = gpu.upload_device_local(self.glyph_vertices, gpu.BUFFER_VERTEX)
            push(self.frame_resources[self.cf], vbuf)
            gpu.cmd_bind_graphics_pipeline(cmd, self.glyph_pipeline)
            gpu.cmd_bind_descriptor_set(cmd, self.sprite_pipe_layout, 0, self.sprite_desc_set, 0)
            gpu.cmd_push_constants(cmd, self.sprite_pipe_layout, gpu.STAGE_VERTEX, self.proj)
            gpu.cmd_bind_vertex_buffer(cmd, vbuf)
            gpu.cmd_draw(cmd, len(self.glyph_vertices) / 8, 1, 0, 0)
            
        # 4. Flush Fonts
        if len(self.font_vertices) > 0:
            let vbuf = gpu.upload_device_local(self.font_vertices, gpu.BUFFER_VERTEX)
            push(self.frame_resources[self.cf], vbuf)
            gpu.cmd_bind_graphics_pipeline(cmd, self.font_pipeline)
            gpu.cmd_bind_descriptor_set(cmd, self.sprite_pipe_layout, 0, self.font_desc_set, 0)
            gpu.cmd_push_constants(cmd, self.sprite_pipe_layout, gpu.STAGE_VERTEX, self.proj)
            gpu.cmd_bind_vertex_buffer(cmd, vbuf)
            gpu.cmd_draw(cmd, len(self.font_vertices) / 8, 1, 0, 0)

    proc draw_part(self, cmd, part, part_idx, score, view_mode):
        let m_idx = 0
        while m_idx < len(part.measures):
            let measure = part.measures[m_idx]
            let pos = get_measure_layout_pos(part_idx, m_idx, score, view_mode)
            self.draw_measure(cmd, measure, pos["x"], pos["y"])
            m_idx = m_idx + 1

    proc draw_measure(self, cmd, measure, x, y):
        # 1. Draw Staff Lines (5 lines, 8px apart)
        let i = 0
        while i < 5:
            let ly = y + i * 8.0
            self.draw_line(cmd, x, ly, x + measure.width, ly, [0.2, 0.2, 0.2, 1.0])
            i = i + 1
        
        # 2. Draw Barline (end of measure)
        self.draw_line(cmd, x + measure.width, y, x + measure.width, y + 32.0, [0.0, 0.0, 0.0, 1.0])

        # Determine if we should draw the clef (only on the first measure of the staff)
        let draw_clef = true
        if measure.parent != nil:
            if len(measure.parent.measures) > 0:
                if measure.parent.measures[0] != measure:
                    draw_clef = false

        if draw_clef:
            # 2.1 Draw Clef
            let clef_glyph = "gClef"
            let clef_y = y + 24.0 # Treble G4 line
            if measure.clef == "bass":
                clef_glyph = "fClef"
                clef_y = y + 8.0 # Bass F3 line
            elif measure.clef == "alto":
                clef_glyph = "cClef"
                clef_y = y + 16.0 # Alto C4 line
            elif measure.clef == "tenor":
                clef_glyph = "cClef"
                clef_y = y + 8.0 # Tenor C4 line (fourth line from bottom)
                
            self.draw_glyph(cmd, clef_glyph, x + 15.0, clef_y, [0.0, 0.0, 0.0, 1.0])

            # 2.2 Draw Key Signature
            let key_sig = measure.key_signature
            let num_accidentals = 0
            if key_sig == "G Major":
                num_accidentals = 1
                self.draw_glyph(cmd, "accidentalSharp", x + 42.0, y + 24.0, [0.0, 0.0, 0.0, 1.0])
            elif key_sig == "F Major":
                num_accidentals = 1
                self.draw_glyph(cmd, "accidentalFlat", x + 42.0, y + 16.0, [0.0, 0.0, 0.0, 1.0])
            elif key_sig == "D Major":
                num_accidentals = 2
                self.draw_glyph(cmd, "accidentalSharp", x + 42.0, y + 24.0, [0.0, 0.0, 0.0, 1.0])
                self.draw_glyph(cmd, "accidentalSharp", x + 50.0, y + 12.0, [0.0, 0.0, 0.0, 1.0])

            # 2.3 Draw Time Signature
            let ts_x = x + 42.0
            if num_accidentals == 1:
                ts_x = x + 55.0
            elif num_accidentals == 2:
                ts_x = x + 65.0

            # PERF-MA-17: Using cached strings instead of str() every frame
            self.draw_text(cmd, measure.ts_top_str, ts_x, y + 22.0, [0.0, 0.0, 0.0, 1.0])
            self.draw_text(cmd, measure.ts_bot_str, ts_x, y + 10.0, [0.0, 0.0, 0.0, 1.0])

        # 3. Draw Elements in voices
        let v_idx = 0
        while v_idx < len(measure.voices):
            let voice = measure.voices[v_idx]
            self.draw_voice(cmd, voice, x, y, measure.clef, draw_clef)
            v_idx = v_idx + 1

    proc draw_voice(self, cmd, voice, x, y, clef, draw_clef):
        let cur_x = x + 20.0
        if draw_clef:
            cur_x = x + 90.0 # Padding for clef + key sig + time sig
        let e_idx = 0
        while e_idx < len(voice.elements):
            let element = voice.elements[e_idx]
            let elem_w = get_element_width(element)
            
            if element.type == "Note":
                self.draw_note(cmd, element, cur_x, y, clef)
                cur_x = cur_x + elem_w
            elif element.type == "Rest":
                self.draw_rest(cmd, element, cur_x, y)
                cur_x = cur_x + elem_w
            e_idx = e_idx + 1

    proc draw_note(self, cmd, note, x, y, clef):
        # Calculate pitch Y offset using layout.pitch_to_y
        let step_offset = pitch_to_y(clef, note.pitch)
        let pitch_y = y + 32.0 - step_offset
        
        let color = [0.0, 0.0, 0.0, 1.0]
        if note.selected:
            color = [0.18, 0.45, 0.90, 1.0]
        elif note.hovered_delete:
            color = [0.85, 0.25, 0.25, 1.0]

        # Draw Notehead
        let nh_glyph = "noteheadBlack"
        if note.duration >= 1.0:
            nh_glyph = "noteheadWhole"
        elif note.duration >= 0.5:
            nh_glyph = "noteheadHalf"
        self.draw_glyph(cmd, nh_glyph, x, pitch_y, color)
        
        # Draw Stem (if not a whole note)
        if note.duration < 1.0:
            self.draw_line(cmd, x + 4, pitch_y, x + 4, pitch_y - 28, color)

        # Draw Ledger Lines if out of staff bounds
        let pos = int(step_offset / 4.0)
        if pos <= -2:
            let lp = -2
            while lp >= pos:
                self.draw_line(cmd, x - 8, y + 32.0 - lp * 4.0, x + 8, y + 32.0 - lp * 4.0, color)
                lp = lp - 2
        elif pos >= 10:
            let lp = 10
            while lp <= pos:
                self.draw_line(cmd, x - 8, y + 32.0 - lp * 4.0, x + 8, y + 32.0 - lp * 4.0, color)
                lp = lp + 2

        # Draw Accidental if present in pitch or note properties
        let acc = ""
        if len(note.pitch) == 3:
            acc = note.pitch[1]
        elif note.accidental != nil:
            acc = note.accidental

        if acc != "":
            self.draw_accidental(cmd, acc, x, pitch_y, color)

    proc draw_note_preview(self, cmd, x, y, duration):
        let color = [0.6, 0.6, 0.6, 0.5] # Semi-transparent light gray
        let nh_glyph = "noteheadBlack"
        if duration >= 1.0:
            nh_glyph = "noteheadWhole"
        elif duration >= 0.5:
            nh_glyph = "noteheadHalf"
        self.draw_glyph(cmd, nh_glyph, x, y, color)
        
        # Draw Stem
        if duration < 1.0:
            self.draw_line(cmd, x + 4, y, x + 4, y - 28, color)

    proc draw_accidental(self, cmd, acc_type, x, y, color):
        let glyph_name = ""
        if acc_type == "#" or acc_type == "sharp":
            glyph_name = "accidentalSharp"
        elif acc_type == "b" or acc_type == "flat":
            glyph_name = "accidentalFlat"
        elif acc_type == "n" or acc_type == "natural":
            glyph_name = "accidentalNatural"
            
        if glyph_name != "":
            self.draw_glyph(cmd, glyph_name, x, y, color)

    proc draw_rest(self, cmd, rest, x, y):
        let color = [0.0, 0.0, 0.0, 1.0]
        if rest.selected:
            color = [0.18, 0.45, 0.90, 1.0]
        elif rest.hovered_delete:
            color = [0.85, 0.25, 0.25, 1.0]
            
        let rest_glyph = "restQuarter"
        if rest.duration >= 1.0:
            rest_glyph = "restWhole"
        elif rest.duration >= 0.5:
            rest_glyph = "restHalf"
        elif rest.duration >= 0.25:
            rest_glyph = "restQuarter"
        elif rest.duration >= 0.125:
            rest_glyph = "restEighth"
        elif rest.duration >= 0.0625:
            rest_glyph = "restSixteenth"
            
        let ref_y = y + 16.0
        if rest_glyph == "restWhole":
            ref_y = y + 8.0 # Sits on 4th line (line index 1 from top)
        elif rest_glyph == "restHalf":
            ref_y = y + 16.0 # Sits on 3rd line
            
        self.draw_glyph(cmd, rest_glyph, x, ref_y, color)

    proc draw_glyph(self, cmd, name, x, y, color):
        # 1. Look up glyph metadata
        if self.atlas_data == nil:
            return
        
        # SEC-EH-16: JSON schema validation
        let glyphs = self.atlas_data["glyphs"]
        if glyphs == nil:
            return
            
        let g = glyphs[name]
        if g == nil:
            return
            
        # 2. Determine texture coords (UVs)
        let tw = self.atlas_data["texture_width"]
        let th = self.atlas_data["texture_height"]
        
        if tw == nil or th == nil or tw == 0.0 or th == 0.0:
            return
        
        let u0 = g["x"] / tw
        let v0 = g["y"] / th
        let u1 = (g["x"] + g["w"]) / tw
        let v1 = (g["y"] + g["h"]) / th
        
        # 3. Calculate position bounds based on offsets
        let px = x
        let py = y
        let pw = g["w"]
        let ph = g["h"]
        
        if name == "noteheadWhole" or name == "noteheadHalf" or name == "noteheadBlack":
            px = x - pw / 2.0
            py = y - ph / 2.0
        elif name == "gClef":
            px = x
            py = y - 76.0
        elif name == "fClef":
            px = x
            py = y - 24.0
        elif name == "cClef":
            px = x
            py = y - 33.0
        elif name == "accidentalSharp":
            px = x - 18.0
            py = y - 22.0
        elif name == "accidentalFlat":
            px = x - 17.0
            py = y - 28.0
        elif name == "accidentalNatural":
            px = x - 14.0
            py = y - 22.0
        elif name == "restWhole":
            px = x - pw / 2.0
            py = y
        elif name == "restHalf":
            px = x - pw / 2.0
            py = y - ph
        elif name == "restQuarter":
            px = x - pw / 2.0
            py = y - ph / 2.0
        elif name == "restEighth":
            px = x - pw / 2.0
            py = y - 10.0
        elif name == "restSixteenth":
            px = x - pw / 2.0
            py = y - 18.0
        
        # 4. Construct vertex data
        let r = color[0]
        let g_val = color[1]
        let b = color[2]
        let a = color[3]
        
        # Triangle 1
        push(self.glyph_vertices, px)
        push(self.glyph_vertices, py)
        push(self.glyph_vertices, u0)
        push(self.glyph_vertices, v0)
        push(self.glyph_vertices, r)
        push(self.glyph_vertices, g_val)
        push(self.glyph_vertices, b)
        push(self.glyph_vertices, a)
        
        push(self.glyph_vertices, px)
        push(self.glyph_vertices, py + ph)
        push(self.glyph_vertices, u0)
        push(self.glyph_vertices, v1)
        push(self.glyph_vertices, r)
        push(self.glyph_vertices, g_val)
        push(self.glyph_vertices, b)
        push(self.glyph_vertices, a)
        
        push(self.glyph_vertices, px + pw)
        push(self.glyph_vertices, py + ph)
        push(self.glyph_vertices, u1)
        push(self.glyph_vertices, v1)
        push(self.glyph_vertices, r)
        push(self.glyph_vertices, g_val)
        push(self.glyph_vertices, b)
        push(self.glyph_vertices, a)
        
        # Triangle 2
        push(self.glyph_vertices, px)
        push(self.glyph_vertices, py)
        push(self.glyph_vertices, u0)
        push(self.glyph_vertices, v0)
        push(self.glyph_vertices, r)
        push(self.glyph_vertices, g_val)
        push(self.glyph_vertices, b)
        push(self.glyph_vertices, a)
        
        push(self.glyph_vertices, px + pw)
        push(self.glyph_vertices, py + ph)
        push(self.glyph_vertices, u1)
        push(self.glyph_vertices, v1)
        push(self.glyph_vertices, r)
        push(self.glyph_vertices, g_val)
        push(self.glyph_vertices, b)
        push(self.glyph_vertices, a)
        
        push(self.glyph_vertices, px + pw)
        push(self.glyph_vertices, py)
        push(self.glyph_vertices, u1)
        push(self.glyph_vertices, v0)
        push(self.glyph_vertices, r)
        push(self.glyph_vertices, g_val)
        push(self.glyph_vertices, b)
        push(self.glyph_vertices, a)

    proc draw_text(self, cmd, text, x, y, color):
        if self.ui_font == nil or self.font_desc_set < 0:
            return
        
        let vertices = gpu.font_text_verts(self.ui_font, text, x, y, color[0], color[1], color[2], color[3])
        if len(vertices) == 0:
            return
            
        let i = 0
        while i < len(vertices):
            push(self.font_vertices, vertices[i])
            i = i + 1

    proc draw_ui(self, cmd, ui_ctx):
        let dl = ui_ctx["draw_list"]
        let i = 0
        while i < len(dl):
            let c = dl[i]
            if c["type"] == "rect":
                self.draw_rect(cmd, c["x"], c["y"], c["w"], c["h"], c["color"])
            elif c["type"] == "text":
                self.draw_text(cmd, c["text"], c["x"], c["y"], c["color"])
            i = i + 1

    proc draw_line(self, cmd, x1, y1, x2, y2, color):
        push(self.line_vertices, x1)
        push(self.line_vertices, y1)
        push(self.line_vertices, 0.0)
        push(self.line_vertices, color[0])
        push(self.line_vertices, color[1])
        push(self.line_vertices, color[2])
        push(self.line_vertices, 0.0)
        push(self.line_vertices, 0.0)
        
        push(self.line_vertices, x2)
        push(self.line_vertices, y2)
        push(self.line_vertices, 0.0)
        push(self.line_vertices, color[0])
        push(self.line_vertices, color[1])
        push(self.line_vertices, color[2])
        push(self.line_vertices, 0.0)
        push(self.line_vertices, 0.0)

    proc draw_rect(self, cmd, x, y, w, h, color):
        let r_val = color[0]
        let g_val = color[1]
        let b_val = color[2]
        
        # TL
        push(self.rect_vertices, x)
        push(self.rect_vertices, y)
        push(self.rect_vertices, 0.0)
        push(self.rect_vertices, r_val)
        push(self.rect_vertices, g_val)
        push(self.rect_vertices, b_val)
        push(self.rect_vertices, 0.0)
        push(self.rect_vertices, 0.0)
        
        # BL
        push(self.rect_vertices, x)
        push(self.rect_vertices, y + h)
        push(self.rect_vertices, 0.0)
        push(self.rect_vertices, r_val)
        push(self.rect_vertices, g_val)
        push(self.rect_vertices, b_val)
        push(self.rect_vertices, 0.0)
        push(self.rect_vertices, 0.0)
        
        # BR
        push(self.rect_vertices, x + w)
        push(self.rect_vertices, y + h)
        push(self.rect_vertices, 0.0)
        push(self.rect_vertices, r_val)
        push(self.rect_vertices, g_val)
        push(self.rect_vertices, b_val)
        push(self.rect_vertices, 0.0)
        push(self.rect_vertices, 0.0)
        
        # TL
        push(self.rect_vertices, x)
        push(self.rect_vertices, y)
        push(self.rect_vertices, 0.0)
        push(self.rect_vertices, r_val)
        push(self.rect_vertices, g_val)
        push(self.rect_vertices, b_val)
        push(self.rect_vertices, 0.0)
        push(self.rect_vertices, 0.0)
        
        # BR
        push(self.rect_vertices, x + w)
        push(self.rect_vertices, y + h)
        push(self.rect_vertices, 0.0)
        push(self.rect_vertices, r_val)
        push(self.rect_vertices, g_val)
        push(self.rect_vertices, b_val)
        push(self.rect_vertices, 0.0)
        push(self.rect_vertices, 0.0)
        
        # TR
        push(self.rect_vertices, x + w)
        push(self.rect_vertices, y)
        push(self.rect_vertices, 0.0)
        push(self.rect_vertices, r_val)
        push(self.rect_vertices, g_val)
        push(self.rect_vertices, b_val)
        push(self.rect_vertices, 0.0)
        push(self.rect_vertices, 0.0)
