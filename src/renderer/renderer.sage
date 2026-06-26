# -----------------------------------------
# renderer.sage - SageMusic GPU Rendering Engine
# Retained-Mode Scene Graph using Vulkan/OpenGL
# -----------------------------------------

import gpu
import io
import json
import graphics.math3d as math3d
import graphics.renderer as base_renderer
from graphics.mesh import mesh_vertex_binding

proc sprite_vertex_attribs():
    let a0 = {}
    a0["location"] = 0
    a0["binding"] = 0
    a0["format"] = gpu.ATTR_VEC2
    a0["offset"] = 0
    
    let a1 = {}
    a1["location"] = 1
    a1["binding"] = 0
    a1["format"] = gpu.ATTR_VEC2
    a1["offset"] = 8
    
    let a2 = {}
    a2["location"] = 2
    a2["binding"] = 0
    a2["format"] = gpu.ATTR_VEC4
    a2["offset"] = 16
    return [a0, a1, a2]
from layout.layout import pitch_to_y, get_measure_layout_pos, get_element_width, STAFF_LINE_GAP, STAFF_HEIGHT, STAFF_STEP

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
        self.glyph_cache = {}

        # 1. Load Atlas Metadata JSON
        let atlas_path = "assets/bravura_atlas.json"
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
        
        # 2. Shader Setup
        self.proj = math3d.mat4_ortho(0, width, 0, height, -1, 1)
        
        let vert = gpu.load_shader("src/renderer/sprite.vert.spv", gpu.STAGE_VERTEX)
        let frag = gpu.load_shader("src/renderer/sprite.frag.spv", gpu.STAGE_FRAGMENT)
        let f_frag = gpu.load_shader("src/renderer/font.frag.spv", gpu.STAGE_FRAGMENT)
        
        if vert < 0 or frag < 0 or f_frag < 0:
            print "Error: Failed to load shaders from src/renderer/"
            return

        # 3. Pipelines
        self.pipe_layout = gpu.create_pipeline_layout([], 64, gpu.STAGE_VERTEX)
        
        # Sprite/Glyph Pipeline Layout
        let b0 = {"binding": 0, "type": gpu.DESC_COMBINED_SAMPLER, "stage": gpu.STAGE_FRAGMENT, "count": 1}
        self.sprite_desc_layout = gpu.create_descriptor_layout([b0])
        self.sprite_pipe_layout = gpu.create_pipeline_layout([self.sprite_desc_layout], 64, gpu.STAGE_VERTEX)
        
        # Line Pipeline
        let line_cfg = {}
        line_cfg["layout"] = self.sprite_pipe_layout
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
        line_cfg["vertex_attribs"] = sprite_vertex_attribs()
        self.line_pipeline = gpu.create_graphics_pipeline(line_cfg)
        
        # Rect Pipeline
        line_cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
        self.rect_pipeline = gpu.create_graphics_pipeline(line_cfg)

        let ps = {"type": gpu.DESC_COMBINED_SAMPLER, "count": 10} # Pool for several sets
        self.sprite_desc_pool = gpu.create_descriptor_pool(10, [ps])
        
        # Glyph Pipeline
        let s_cfg = {}
        s_cfg["layout"] = self.sprite_pipe_layout
        s_cfg["render_pass"] = self.base["render_pass"]
        s_cfg["vertex_shader"] = vert
        s_cfg["fragment_shader"] = frag
        s_cfg["topology"] = gpu.TOPO_TRIANGLE_LIST
        s_cfg["cull_mode"] = gpu.CULL_NONE
        s_cfg["front_face"] = gpu.FRONT_CCW
        s_cfg["depth_test"] = false
        s_cfg["depth_write"] = false
        s_cfg["blend"] = true
        s_cfg["vertex_bindings"] = [mesh_vertex_binding()]
        s_cfg["vertex_attribs"] = sprite_vertex_attribs()
        self.glyph_pipeline = gpu.create_graphics_pipeline(s_cfg)
        
        # Font Pipeline
        s_cfg["fragment_shader"] = f_frag
        self.font_pipeline = gpu.create_graphics_pipeline(s_cfg)

        # 4. Load Textures
        self.sprite_texture = gpu.load_texture("assets/bravura_atlas.png")
        self.sprite_sampler = gpu.create_sampler(gpu.FILTER_LINEAR, gpu.FILTER_LINEAR, gpu.ADDRESS_CLAMP_EDGE)
        self.sprite_desc_set = gpu.allocate_descriptor_set(self.sprite_desc_pool, self.sprite_desc_layout)
        gpu.update_descriptor_image(self.sprite_desc_set, 0, self.sprite_texture, self.sprite_sampler)
        
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

        # 5. Resource Tracking
        self.frame_resources = []
        let i = 0
        while i < len(self.base["framebuffers"]):
            push(self.frame_resources, [])
            i = i + 1
        self.cf = 0
        
        # 6. Batching Arrays
        self.batch_lines = []
        self.batch_rects = []
        self.batch_glyphs = []
        self.batch_fonts = []
        
        # 7. Safe solid UV for lines and rects
        self.solid_u = 0.0
        self.solid_v = 0.0
        if self.atlas_data != nil:
            let glyphs = self.atlas_data["glyphs"]
            if glyphs != nil:
                let g = glyphs["noteheadBlack"]
                if g != nil:
                    self.solid_u = (g["x"] + g["w"]/2.0) / self.atlas_data["texture_width"]
                    self.solid_v = (g["y"] + g["h"]/2.0) / self.atlas_data["texture_height"]

    proc begin_frame(self):
        let frame_info = base_renderer.begin_frame(self.base)
        if frame_info != nil:
            self.cf = frame_info["current_frame"]
            let res_list = self.frame_resources[self.cf]
            let i = 0
            while i < len(res_list):
                gpu.destroy_buffer(res_list[i])
                i = i + 1
            self.frame_resources[self.cf] = []
        return frame_info

    proc end_frame(self, frame_info):
        base_renderer.end_frame(self.base, frame_info)

    proc cleanup(self):
        # Cleanup all GPU resources
        if self.line_pipeline >= 0:
            gpu.destroy_pipeline(self.line_pipeline)
        if self.rect_pipeline >= 0:
            gpu.destroy_pipeline(self.rect_pipeline)
        if self.glyph_pipeline >= 0:
            gpu.destroy_pipeline(self.glyph_pipeline)
        if self.font_pipeline >= 0:
            gpu.destroy_pipeline(self.font_pipeline)
        if self.pipe_layout >= 0:
            gpu.destroy_pipeline_layout(self.pipe_layout)
        if self.sprite_pipe_layout >= 0:
            gpu.destroy_pipeline_layout(self.sprite_pipe_layout)
        if self.sprite_desc_layout >= 0:
            gpu.destroy_descriptor_layout(self.sprite_desc_layout)
        if self.sprite_texture >= 0:
            gpu.destroy_texture(self.sprite_texture)
        if self.sprite_sampler >= 0:
            gpu.destroy_sampler(self.sprite_sampler)
        if self.sprite_desc_pool >= 0:
            gpu.destroy_descriptor_pool(self.sprite_desc_pool)

    proc recreate_swapchain(self):
        gpu.recreate_swapchain()
        self.frame_resources = []
        let i = 0
        while i < len(self.base["framebuffers"]):
            push(self.frame_resources, [])
            i = i + 1
        self.cf = 0

    proc draw_score(self, frame_info, score, view_mode):
        let cmd = frame_info["cmd"]
        self.clear_batches()
        
        # 1. Background (Must be first)
        self.add_rect(250.0, 0.0, self.base["width"] - 250.0, self.base["height"], [0.98, 0.98, 0.96, 1.0])
        self.flush_batches(cmd)
        
        # 2. Manuscript Elements
        let part_idx = 0
        while part_idx < len(score.parts):
            let part = score.parts[part_idx]
            let m_idx = 0
            while m_idx < len(part.measures):
                let measure = part.measures[m_idx]
                let pos = get_measure_layout_pos(part_idx, m_idx, score, view_mode)
                
                if pos["x"] + measure.width >= 0.0 and pos["x"] <= self.base["width"]:
                    self.draw_measure(cmd, measure, pos["x"], pos["y"])
                m_idx = m_idx + 1
            part_idx = part_idx + 1

        if self.preview_info != nil:
            let pr = self.preview_info
            self.draw_note_preview(cmd, pr["x"], pr["y"], pr["duration"])
            
        self.flush_batches(cmd)

    proc draw_ui(self, cmd, ui_ctx):
        self.clear_batches()
        let dl = ui_ctx["draw_list"]
        let i = 0
        while i < len(dl):
            let c = dl[i]
            if c["type"] == "rect":
                self.add_rect(c["x"], c["y"], c["w"], c["h"], c["color"])
            elif c["type"] == "text":
                self.add_text(c["text"], c["x"], c["y"], c["color"])
            i = i + 1
        self.flush_batches(cmd)

    proc clear_batches(self):
        self.batch_lines = []
        self.batch_rects = []
        self.batch_glyphs = []
        self.batch_fonts = []

    proc flush_batches(self, cmd):
        # 1. Rects
        if len(self.batch_rects) > 0:
            let vbuf = gpu.upload_device_local(self.batch_rects, gpu.BUFFER_VERTEX)
            push(self.frame_resources[self.cf], vbuf)
            gpu.cmd_bind_graphics_pipeline(cmd, self.rect_pipeline)
            gpu.cmd_bind_descriptor_set(cmd, self.sprite_pipe_layout, 0, self.sprite_desc_set, 0)
            gpu.cmd_push_constants(cmd, self.sprite_pipe_layout, gpu.STAGE_VERTEX, self.proj)
            gpu.cmd_bind_vertex_buffer(cmd, vbuf)
            gpu.cmd_draw(cmd, len(self.batch_rects) / 8, 1, 0, 0)
            self.batch_rects = []
            
        # 2. Lines
        if len(self.batch_lines) > 0:
            let vbuf = gpu.upload_device_local(self.batch_lines, gpu.BUFFER_VERTEX)
            push(self.frame_resources[self.cf], vbuf)
            gpu.cmd_bind_graphics_pipeline(cmd, self.line_pipeline)
            gpu.cmd_bind_descriptor_set(cmd, self.sprite_pipe_layout, 0, self.sprite_desc_set, 0)
            gpu.cmd_push_constants(cmd, self.sprite_pipe_layout, gpu.STAGE_VERTEX, self.proj)
            gpu.cmd_bind_vertex_buffer(cmd, vbuf)
            gpu.cmd_draw(cmd, len(self.batch_lines) / 8, 1, 0, 0)
            self.batch_lines = []
            
        # 3. Glyphs
        if len(self.batch_glyphs) > 0:
            let vbuf = gpu.upload_device_local(self.batch_glyphs, gpu.BUFFER_VERTEX)
            push(self.frame_resources[self.cf], vbuf)
            gpu.cmd_bind_graphics_pipeline(cmd, self.glyph_pipeline)
            gpu.cmd_bind_descriptor_set(cmd, self.sprite_pipe_layout, 0, self.sprite_desc_set, 0)
            gpu.cmd_push_constants(cmd, self.sprite_pipe_layout, gpu.STAGE_VERTEX, self.proj)
            gpu.cmd_bind_vertex_buffer(cmd, vbuf)
            gpu.cmd_draw(cmd, len(self.batch_glyphs) / 8, 1, 0, 0)
            self.batch_glyphs = []
            
        # 4. Fonts
        if len(self.batch_fonts) > 0:
            let vbuf = gpu.upload_device_local(self.batch_fonts, gpu.BUFFER_VERTEX)
            push(self.frame_resources[self.cf], vbuf)
            gpu.cmd_bind_graphics_pipeline(cmd, self.font_pipeline)
            gpu.cmd_bind_descriptor_set(cmd, self.sprite_pipe_layout, 0, self.font_desc_set, 0)
            gpu.cmd_push_constants(cmd, self.sprite_pipe_layout, gpu.STAGE_VERTEX, self.proj)
            gpu.cmd_bind_vertex_buffer(cmd, vbuf)
            gpu.cmd_draw(cmd, len(self.batch_fonts) / 8, 1, 0, 0)
            self.batch_fonts = []

    proc draw_measure(self, cmd, measure, x, y):
        # Staff Lines
        let i = 0
        while i < 5:
            let ly = y + i * STAFF_LINE_GAP
            self.add_line(x, ly, x + measure.width, ly, [0.2, 0.2, 0.2, 1.0])
            i = i + 1
        self.add_line(x + measure.width, y, x + measure.width, y + STAFF_HEIGHT, [0.0, 0.0, 0.0, 1.0])

        let draw_clef = true
        if measure.parent != nil and len(measure.parent.measures) > 0:
            if measure.parent.measures[0] != measure:
                draw_clef = false

        if draw_clef:
            self.add_glyph(measure.clef + "Clef", x + 15.0, y + 24.0, [0.0, 0.0, 0.0, 1.0])
            self.add_text(measure.ts_top_str, x + 42.0, y + 22.0, [0.0, 0.0, 0.0, 1.0])
            self.add_text(measure.ts_bot_str, x + 42.0, y + 10.0, [0.0, 0.0, 0.0, 1.0])

        let v_idx = 0
        while v_idx < len(measure.voices):
            self.draw_voice(cmd, measure.voices[v_idx], x, y, measure.clef, draw_clef)
            v_idx = v_idx + 1

    proc draw_voice(self, cmd, voice, x, y, clef, draw_clef):
        let cur_x = x + 20.0
        if draw_clef: cur_x = x + 90.0
        let e_idx = 0
        while e_idx < len(voice.elements):
            let element = voice.elements[e_idx]
            let elem_w = get_element_width(element)
            if element.type == "Note":
                self.draw_note(cmd, element, cur_x, y, clef)
            elif element.type == "Rest":
                self.draw_rest(cmd, element, cur_x, y)
            cur_x = cur_x + elem_w
            e_idx = e_idx + 1

    proc draw_note(self, cmd, note, x, y, clef):
        let step_offset = pitch_to_y(clef, note.pitch)
        let pitch_y = y + STAFF_HEIGHT - step_offset
        let color = [0.0, 0.0, 0.0, 1.0]
        if note.selected: color = [0.18, 0.45, 0.90, 1.0]
        elif note.hovered_delete: color = [0.85, 0.25, 0.25, 1.0]

        let nh = "noteheadBlack"
        if note.duration >= 1.0: nh = "noteheadWhole"
        elif note.duration >= 0.5: nh = "noteheadHalf"
        self.add_glyph(nh, x, pitch_y, color)
        if note.duration < 1.0: self.add_line(x + 4, pitch_y, x + 4, pitch_y - 28, color)
        
        let pos = int(step_offset / STAFF_STEP)
        if pos <= -2:
            let lp = -2
            while lp >= pos:
                self.add_line(x - 8, y + STAFF_HEIGHT - lp * STAFF_STEP, x + 8, y + STAFF_HEIGHT - lp * STAFF_STEP, color)
                lp = lp - 2
        elif pos >= 10:
            let lp = 10
            while lp <= pos:
                self.add_line(x - 8, y + STAFF_HEIGHT - lp * STAFF_STEP, x + 8, y + STAFF_HEIGHT - lp * STAFF_STEP, color)
                lp = lp + 2
        
        let acc = ""
        if len(note.pitch) == 3: acc = note.pitch[1]
        elif note.accidental != nil: acc = note.accidental
        if acc != "": self.draw_accidental(cmd, acc, x, pitch_y, color)

    proc draw_accidental(self, cmd, acc, x, y, color):
        let gn = ""
        if acc == "#" or acc == "sharp": gn = "accidentalSharp"
        elif acc == "b" or acc == "flat": gn = "accidentalFlat"
        elif acc == "n" or acc == "natural": gn = "accidentalNatural"
        if gn != "": self.add_glyph(gn, x, y, color)

    proc draw_rest(self, cmd, rest, x, y):
        let color = [0.0, 0.0, 0.0, 1.0]
        if rest.selected: color = [0.18, 0.45, 0.90, 1.0]
        elif rest.hovered_delete: color = [0.85, 0.25, 0.25, 1.0]
        let rg = "restQuarter"
        if rest.duration >= 1.0: rg = "restWhole"
        elif rest.duration >= 0.5: rg = "restHalf"
        elif rest.duration >= 0.125: rg = "restEighth"
        elif rest.duration >= 0.0625: rg = "restSixteenth"
        let ry = y + STAFF_HEIGHT / 2.0
        if rg == "restWhole": ry = y + STAFF_LINE_GAP
        elif rg == "restHalf": ry = y + STAFF_HEIGHT / 2.0
        self.add_glyph(rg, x, ry, color)

    proc draw_note_preview(self, cmd, x, y, dur):
        let c = [0.6, 0.6, 0.6, 0.5]
        let nh = "noteheadBlack"
        if dur >= 1.0: nh = "noteheadWhole"
        elif dur >= 0.5: nh = "noteheadHalf"
        self.add_glyph(nh, x, y, c)
        if dur < 1.0: self.add_line(x + 4, y, x + 4, y - 28, c)

    proc add_line(self, x1, y1, x2, y2, c):
        push(self.batch_lines, x1)
        push(self.batch_lines, y1)
        push(self.batch_lines, self.solid_u)
        push(self.batch_lines, self.solid_v)
        push(self.batch_lines, c[0])
        push(self.batch_lines, c[1])
        push(self.batch_lines, c[2])
        push(self.batch_lines, c[3])
        
        push(self.batch_lines, x2)
        push(self.batch_lines, y2)
        push(self.batch_lines, self.solid_u)
        push(self.batch_lines, self.solid_v)
        push(self.batch_lines, c[0])
        push(self.batch_lines, c[1])
        push(self.batch_lines, c[2])
        push(self.batch_lines, c[3])

    proc add_rect(self, x, y, w, h, c):
        let r=c[0]
        let g=c[1]
        let b=c[2]
        let a=c[3]
        let su = self.solid_u
        let sv = self.solid_v
        push(self.batch_rects, x)
        push(self.batch_rects, y)
        push(self.batch_rects, su)
        push(self.batch_rects, sv)
        push(self.batch_rects, r)
        push(self.batch_rects, g)
        push(self.batch_rects, b)
        push(self.batch_rects, a)
        
        push(self.batch_rects, x)
        push(self.batch_rects, y+h)
        push(self.batch_rects, su)
        push(self.batch_rects, sv)
        push(self.batch_rects, r)
        push(self.batch_rects, g)
        push(self.batch_rects, b)
        push(self.batch_rects, a)
        
        push(self.batch_rects, x+w)
        push(self.batch_rects, y+h)
        push(self.batch_rects, su)
        push(self.batch_rects, sv)
        push(self.batch_rects, r)
        push(self.batch_rects, g)
        push(self.batch_rects, b)
        push(self.batch_rects, a)
        
        push(self.batch_rects, x)
        push(self.batch_rects, y)
        push(self.batch_rects, su)
        push(self.batch_rects, sv)
        push(self.batch_rects, r)
        push(self.batch_rects, g)
        push(self.batch_rects, b)
        push(self.batch_rects, a)
        
        push(self.batch_rects, x+w)
        push(self.batch_rects, y+h)
        push(self.batch_rects, su)
        push(self.batch_rects, sv)
        push(self.batch_rects, r)
        push(self.batch_rects, g)
        push(self.batch_rects, b)
        push(self.batch_rects, a)
        
        push(self.batch_rects, x+w)
        push(self.batch_rects, y)
        push(self.batch_rects, su)
        push(self.batch_rects, sv)
        push(self.batch_rects, r)
        push(self.batch_rects, g)
        push(self.batch_rects, b)
        push(self.batch_rects, a)

    proc add_glyph(self, name, x, y, color):
        if self.atlas_data == nil: return
        let g = self.glyph_cache[name]
        if g == nil:
            let glyphs = self.atlas_data["glyphs"]
            if glyphs == nil: return
            g = glyphs[name]
            if g == nil: return
            self.glyph_cache[name] = g
        let tw = self.atlas_data["texture_width"]
        let th = self.atlas_data["texture_height"]
        if tw == nil or th == nil or tw == 0.0 or th == 0.0: return
        let u0 = g["x"]/tw
        let v0 = g["y"]/th
        let u1 = (g["x"]+g["w"])/tw
        let v1 = (g["y"]+g["h"])/th
        let px = x
        let py = y
        let pw = g["w"]
        let ph = g["h"]
        if name == "noteheadWhole" or name == "noteheadHalf" or name == "noteheadBlack":
            px = x-pw/2.0
            py = y-ph/2.0
        elif name == "gClef": py = y-76.0
        elif name == "fClef": py = y-24.0
        elif name == "cClef": py = y-33.0
        elif name == "accidentalSharp":
            px = x-18.0
            py = y-22.0
        elif name == "accidentalFlat":
            px = x-17.0
            py = y-28.0
        elif name == "accidentalNatural":
            px = x-14.0
            py = y-22.0
        elif name == "restWhole": px = x-pw/2.0
        elif name == "restHalf":
            px = x-pw/2.0
            py = y-ph
        elif name == "restQuarter":
            px = x-pw/2.0
            py = y-ph/2.0
        elif name == "restEighth":
            px = x-pw/2.0
            py = y-10.0
        elif name == "restSixteenth":
            px = x-pw/2.0
            py = y-18.0
        let r=color[0]
        let g_v=color[1]
        let b=color[2]
        let a=color[3]
        
        push(self.batch_glyphs, px)
        push(self.batch_glyphs, py)
        push(self.batch_glyphs, u0)
        push(self.batch_glyphs, v0)
        push(self.batch_glyphs, r)
        push(self.batch_glyphs, g_v)
        push(self.batch_glyphs, b)
        push(self.batch_glyphs, a)
        
        push(self.batch_glyphs, px)
        push(self.batch_glyphs, py+ph)
        push(self.batch_glyphs, u0)
        push(self.batch_glyphs, v1)
        push(self.batch_glyphs, r)
        push(self.batch_glyphs, g_v)
        push(self.batch_glyphs, b)
        push(self.batch_glyphs, a)
        
        push(self.batch_glyphs, px+pw)
        push(self.batch_glyphs, py+ph)
        push(self.batch_glyphs, u1)
        push(self.batch_glyphs, v1)
        push(self.batch_glyphs, r)
        push(self.batch_glyphs, g_v)
        push(self.batch_glyphs, b)
        push(self.batch_glyphs, a)
        
        push(self.batch_glyphs, px)
        push(self.batch_glyphs, py)
        push(self.batch_glyphs, u0)
        push(self.batch_glyphs, v0)
        push(self.batch_glyphs, r)
        push(self.batch_glyphs, g_v)
        push(self.batch_glyphs, b)
        push(self.batch_glyphs, a)
        
        push(self.batch_glyphs, px+pw)
        push(self.batch_glyphs, py+ph)
        push(self.batch_glyphs, u1)
        push(self.batch_glyphs, v1)
        push(self.batch_glyphs, r)
        push(self.batch_glyphs, g_v)
        push(self.batch_glyphs, b)
        push(self.batch_glyphs, a)
        
        push(self.batch_glyphs, px+pw)
        push(self.batch_glyphs, py)
        push(self.batch_glyphs, u1)
        push(self.batch_glyphs, v0)
        push(self.batch_glyphs, r)
        push(self.batch_glyphs, g_v)
        push(self.batch_glyphs, b)
        push(self.batch_glyphs, a)

    proc add_text(self, text, x, y, color):
        if self.ui_font == nil: return
        let vertices = gpu.font_text_verts(self.ui_font, text, x, y, color[0], color[1], color[2], color[3])
        let i = 0
        while i < len(vertices):
            push(self.batch_fonts, vertices[i])
            i = i + 1

    proc draw_glyph(self, cmd, name, x, y, color):
        self.add_glyph(name, x, y, color) # Compatibility
