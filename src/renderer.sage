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
from layout import pitch_to_y

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
        if io.exists("assets/bravura_atlas.json"):
            let meta_str = io.readfile("assets/bravura_atlas.json")
            let root = json.cJSON_Parse(meta_str)
            self.atlas_data = json.cJSON_ToSage(root)
            json.cJSON_Delete(root)
        else:
            self.atlas_data = nil
        
        # Shader constants (Projection Matrix)
        self.proj = math3d.mat4_ortho(0, width, 0, height, -1, 1)
        
        # Shaders (Reusing pre-compiled shader modules)
        let vert = gpu.load_shader("../SageLang/core/examples/shaders/cube.vert.spv", gpu.STAGE_VERTEX)
        let frag = gpu.load_shader("../SageLang/core/examples/shaders/text3d.frag.spv", gpu.STAGE_FRAGMENT)
        if vert < 0 or frag < 0:
            raise "Failed to load primitive shaders"

        # Pipeline Layout (64-byte push constant for projection matrix)
        self.pipe_layout = gpu.create_pipeline_layout([], 64, gpu.STAGE_VERTEX)
        if self.pipe_layout < 0:
            raise "Failed to create pipeline layout"

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
        self.sprite_texture = gpu.load_texture("assets/bravura_atlas.png")
        self.sprite_sampler = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_CLAMP_EDGE)
        gpu.update_descriptor_image(self.sprite_desc_set, 0, self.sprite_texture, self.sprite_sampler)
        
        # 3.1 Load UI Font (Lato)
        if io.exists("assets/lato.ttf"):
            self.ui_font = gpu.load_font("assets/lato.ttf", 16)
            let f_atlas = gpu.font_atlas(self.ui_font)
            let f_tex = gpu.load_texture(f_atlas["path"])
            let f_smp = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_CLAMP_EDGE)
            gpu.font_set_atlas(self.ui_font, f_tex, f_smp)
            
            self.font_desc_set = gpu.allocate_descriptor_set(self.sprite_desc_pool, self.sprite_desc_layout)
            gpu.update_descriptor_image(self.font_desc_set, 0, f_tex, f_smp)
        else:
            self.ui_font = nil
            self.font_desc_set = -1
            
        # 4. Pipeline Layout (64-byte projection matrix + 1 descriptor set)
        self.sprite_pipe_layout = gpu.create_pipeline_layout([self.sprite_desc_layout], 64, gpu.STAGE_VERTEX)
        
        # 5. Load Compiled Shaders
        let vert_shader = gpu.load_shader("src/sprite.vert.spv", gpu.STAGE_VERTEX)
        let frag_shader = gpu.load_shader("src/sprite.frag.spv", gpu.STAGE_FRAGMENT)
        let font_frag_shader = gpu.load_shader("src/font.frag.spv", gpu.STAGE_FRAGMENT)
        if vert_shader < 0 or frag_shader < 0 or font_frag_shader < 0:
            raise "Failed to load sprite or font shaders"
        
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
            raise "Failed to create glyph pipeline"
            
        # Create font pipeline
        s_cfg["fragment_shader"] = font_frag_shader
        self.font_pipeline = gpu.create_graphics_pipeline(s_cfg)
        if self.font_pipeline < 0:
            raise "Failed to create font pipeline"
            
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
        let ok = gpu.recreate_swapchain()
        if ok == false:
            return false

        let r = self.base
        let i = 0
        while i < len(r["framebuffers"]):
            gpu.destroy_framebuffer(r["framebuffers"][i])
            i = i + 1

        gpu.destroy_image(r["depth_image"])

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

    proc draw_score(self, frame_info, score):
        self.cf = frame_info["current_frame"]
        let cmd = frame_info["cmd"]
        let rp = self.base["render_pass"]
        let fb = self.base["framebuffers"][frame_info["image_index"]]
        
        # Clear color: Paper White
        gpu.cmd_begin_render_pass(cmd, rp, fb, [[0.98, 0.98, 0.96, 1.0], [1.0, 0]])
        
        # Iterate through parts, systems, and measures
        let cur_y = 100.0
        let part_idx = 0
        while part_idx < len(score.parts):
            let part = score.parts[part_idx]
            self.draw_part(cmd, part, cur_y)
            cur_y = cur_y + 200.0 # Vertical system spacing
            part_idx = part_idx + 1

        if self.preview_info != nil:
            let pr = self.preview_info
            self.draw_note_preview(cmd, pr["x"], pr["y"], pr["duration"])

    proc draw_part(self, cmd, part, y):
        let cur_x = 50.0
        let m_idx = 0
        while m_idx < len(part.measures):
            let measure = part.measures[m_idx]
            self.draw_measure(cmd, measure, cur_x, y)
            cur_x = cur_x + measure.width
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

        # 3. Draw Elements in voices
        let v_idx = 0
        while v_idx < len(measure.voices):
            let voice = measure.voices[v_idx]
            self.draw_voice(cmd, voice, x, y, measure.clef)
            v_idx = v_idx + 1

    proc draw_voice(self, cmd, voice, x, y, clef):
        let cur_x = x + 65.0 # Padding for clef
        let e_idx = 0
        while e_idx < len(voice.elements):
            let element = voice.elements[e_idx]
            # Simple layout: linear placement
            if type(element) == "Note":
                self.draw_note(cmd, element, cur_x, y, clef)
                cur_x = cur_x + 50.0
            elif type(element) == "Rest":
                self.draw_rest(cmd, element, cur_x, y)
                cur_x = cur_x + 50.0
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
        
        let glyphs = self.atlas_data["glyphs"]
        let g = glyphs[name]
        if g == nil:
            return
            
        # 2. Determine texture coords (UVs)
        let tw = self.atlas_data["texture_width"]
        let th = self.atlas_data["texture_height"]
        
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
        
        let vertices = [
            px, py,        u0, v0,  r, g_val, b, a,
            px, py + ph,   u0, v1,  r, g_val, b, a,
            px + pw, py + ph, u1, v1,  r, g_val, b, a,
            
            px, py,        u0, v0,  r, g_val, b, a,
            px + pw, py + ph, u1, v1,  r, g_val, b, a,
            px + pw, py,   u1, v0,  r, g_val, b, a
        ]
        
        let vbuf = gpu.upload_device_local(vertices, gpu.BUFFER_VERTEX)
        push(self.frame_resources[self.cf], vbuf)
        
        # 5. Draw sprite using graphics pipeline (passing 0 for VK_PIPELINE_BIND_POINT_GRAPHICS)
        gpu.cmd_bind_graphics_pipeline(cmd, self.glyph_pipeline)
        gpu.cmd_bind_descriptor_set(cmd, self.sprite_pipe_layout, 0, self.sprite_desc_set, 0)
        gpu.cmd_push_constants(cmd, self.sprite_pipe_layout, gpu.STAGE_VERTEX, self.proj)
        gpu.cmd_bind_vertex_buffer(cmd, vbuf)
        gpu.cmd_draw(cmd, 6, 1, 0, 0)

    proc draw_text(self, cmd, text, x, y, color):
        if self.ui_font == nil or self.font_desc_set < 0:
            return
        
        let vertices = gpu.font_text_verts(self.ui_font, text, x, y, color[0], color[1], color[2], color[3])
        if len(vertices) == 0:
            return
            
        let vbuf = gpu.upload_device_local(vertices, gpu.BUFFER_VERTEX)
        push(self.frame_resources[self.cf], vbuf)
        
        gpu.cmd_bind_graphics_pipeline(cmd, self.font_pipeline)
        gpu.cmd_bind_descriptor_set(cmd, self.sprite_pipe_layout, 0, self.font_desc_set, 0)
        gpu.cmd_push_constants(cmd, self.sprite_pipe_layout, gpu.STAGE_VERTEX, self.proj)
        gpu.cmd_bind_vertex_buffer(cmd, vbuf)
        gpu.cmd_draw(cmd, len(vertices) / 8, 1, 0, 0)

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
        let vertices = [
            x1, y1, 0.0,  color[0], color[1], color[2],  0.0, 0.0,
            x2, y2, 0.0,  color[0], color[1], color[2],  0.0, 0.0
        ]
        let vbuf = gpu.upload_device_local(vertices, gpu.BUFFER_VERTEX)
        push(self.frame_resources[self.cf], vbuf)
        
        gpu.cmd_bind_graphics_pipeline(cmd, self.line_pipeline)
        gpu.cmd_push_constants(cmd, self.pipe_layout, gpu.STAGE_VERTEX, self.proj)
        gpu.cmd_bind_vertex_buffer(cmd, vbuf)
        gpu.cmd_draw(cmd, 2, 1, 0, 0)

    proc draw_rect(self, cmd, x, y, w, h, color):
        let r_val = color[0]
        let g_val = color[1]
        let b_val = color[2]
        
        let vertices = [
            x, y, 0.0,      r_val, g_val, b_val,  0.0, 0.0,  # TL
            x, y + h, 0.0,  r_val, g_val, b_val,  0.0, 0.0,  # BL
            x + w, y + h, 0.0, r_val, g_val, b_val, 0.0, 0.0,  # BR
            
            x, y, 0.0,      r_val, g_val, b_val,  0.0, 0.0,  # TL
            x + w, y + h, 0.0, r_val, g_val, b_val, 0.0, 0.0,  # BR
            x + w, y, 0.0,  r_val, g_val, b_val,  0.0, 0.0   # TR
        ]
        let vbuf = gpu.upload_device_local(vertices, gpu.BUFFER_VERTEX)
        push(self.frame_resources[self.cf], vbuf)
        
        gpu.cmd_bind_graphics_pipeline(cmd, self.rect_pipeline)
        gpu.cmd_push_constants(cmd, self.pipe_layout, gpu.STAGE_VERTEX, self.proj)
        gpu.cmd_bind_vertex_buffer(cmd, vbuf)
        gpu.cmd_draw(cmd, 6, 1, 0, 0)
