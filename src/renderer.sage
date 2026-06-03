# -----------------------------------------
# renderer.sage - SageMusic GPU Rendering Engine
# Retained-Mode Scene Graph using Vulkan/OpenGL
# -----------------------------------------

import gpu
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
        
        # Shader constants (Projection Matrix)
        self.proj = math3d.mat4_ortho(0, width, height, 0, -1, 1)
        
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
        # Placeholder for textured quad pipeline
        return nil

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

        # 3. Draw Elements in voices
        let v_idx = 0
        while v_idx < len(measure.voices):
            let voice = measure.voices[v_idx]
            self.draw_voice(cmd, voice, x, y, measure.clef)
            v_idx = v_idx + 1

    proc draw_voice(self, cmd, voice, x, y, clef):
        let cur_x = x + 20.0 # Initial padding for clef/key
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
        
        # Draw Notehead (as a small rect for now, will be glyph)
        self.draw_rect(cmd, x - 4, pitch_y - 3, 8, 6, [0, 0, 0, 1.0])
        
        # Draw Stem (if not a whole note)
        if note.duration < 1.0:
            self.draw_line(cmd, x + 4, pitch_y, x + 4, pitch_y - 28, [0, 0, 0, 1.0])

        # Draw Ledger Lines if out of staff bounds
        let pos = int(step_offset / 4.0)
        if pos <= -2:
            let lp = -2
            while lp >= pos:
                self.draw_line(cmd, x - 8, y + 32.0 - lp * 4.0, x + 8, y + 32.0 - lp * 4.0, [0.0, 0.0, 0.0, 1.0])
                lp = lp - 2
        elif pos >= 10:
            let lp = 10
            while lp <= pos:
                self.draw_line(cmd, x - 8, y + 32.0 - lp * 4.0, x + 8, y + 32.0 - lp * 4.0, [0.0, 0.0, 0.0, 1.0])
                lp = lp + 2

        # Draw Accidental if present in pitch or note properties
        let acc = ""
        if len(note.pitch) == 3:
            acc = note.pitch[1]
        elif note.accidental != nil:
            acc = note.accidental

        if acc != "":
            self.draw_accidental(cmd, acc, x, pitch_y)

    proc draw_accidental(self, cmd, acc_type, x, y):
        if acc_type == "#" or acc_type == "sharp":
            # Two vertical lines
            self.draw_line(cmd, x - 14, y - 8, x - 14, y + 8, [0, 0, 0, 1])
            self.draw_line(cmd, x - 10, y - 8, x - 10, y + 8, [0, 0, 0, 1])
            # Two horizontal lines
            self.draw_line(cmd, x - 17, y - 3, x - 7, y - 3, [0, 0, 0, 1])
            self.draw_line(cmd, x - 17, y + 3, x - 7, y + 3, [0, 0, 0, 1])
        elif acc_type == "b" or acc_type == "flat":
            # Vertical stem
            self.draw_line(cmd, x - 14, y - 8, x - 14, y + 4, [0, 0, 0, 1])
            # Small loop box
            self.draw_rect(cmd, x - 14, y - 1, 5, 5, [0, 0, 0, 1])
        elif acc_type == "n" or acc_type == "natural":
            # Left stem
            self.draw_line(cmd, x - 14, y - 8, x - 14, y + 4, [0, 0, 0, 1])
            # Right stem
            self.draw_line(cmd, x - 10, y - 4, x - 10, y + 8, [0, 0, 0, 1])
            # Cross bars
            self.draw_line(cmd, x - 14, y - 4, x - 10, y - 4, [0, 0, 0, 1])
            self.draw_line(cmd, x - 14, y + 4, x - 10, y + 4, [0, 0, 0, 1])

    proc draw_rest(self, cmd, rest, x, y):
        # Draw Rest (as a small box)
        self.draw_rect(cmd, x - 3, y + 12, 6, 8, [0.4, 0.4, 0.4, 1.0])

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
