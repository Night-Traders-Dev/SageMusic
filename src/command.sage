# -----------------------------------------
# command.sage - SageMusic Undo/Redo Engine
# Command Pattern implementation for score history
# -----------------------------------------

class Command:
    proc execute(self):
        pass
    proc undo(self):
        pass

class AddElementCommand(Command):
    proc init(self, voice, element):
        self.voice = voice
        self.element = element

    proc execute(self):
        # Set element's parent to the voice
        self.element.parent = self.voice
        push(self.voice.elements, self.element)

    proc undo(self):
        # Remove element from voice
        let new_list = []
        let i = 0
        while i < len(self.voice.elements):
            if self.voice.elements[i] != self.element:
                push(new_list, self.voice.elements[i])
            i = i + 1
        self.voice.elements = new_list

class DeleteElementCommand(Command):
    proc init(self, voice, element):
        self.voice = voice
        self.element = element
        self.index = -1
        
        # Locate the element to preserve its insertion index
        let i = 0
        while i < len(voice.elements):
            if voice.elements[i] == element:
                self.index = i
                break
            i = i + 1

    proc execute(self):
        if self.index >= 0:
            let new_list = []
            let i = 0
            while i < len(self.voice.elements):
                if i != self.index:
                    push(new_list, self.voice.elements[i])
                i = i + 1
            self.voice.elements = new_list

    proc undo(self):
        if self.index >= 0:
            let new_list = []
            let i = 0
            while i < len(self.voice.elements):
                if i == self.index:
                    push(new_list, self.element)
                push(new_list, self.voice.elements[i])
                i = i + 1
            if len(new_list) == len(self.voice.elements):
                push(new_list, self.element)
            self.voice.elements = new_list

class CommandHistory:
    proc init(self):
        self.undo_stack = []
        self.redo_stack = []

    proc execute(self, cmd):
        cmd.execute()
        push(self.undo_stack, cmd)
        self.redo_stack = [] # Clear redo stack on new action

    proc undo(self):
        if len(self.undo_stack) == 0:
            return
        
        let last_idx = len(self.undo_stack) - 1
        let cmd = self.undo_stack[last_idx]
        
        # Pop from undo_stack
        let new_undo = []
        let i = 0
        while i < last_idx:
            push(new_undo, self.undo_stack[i])
            i = i + 1
        self.undo_stack = new_undo
        
        cmd.undo()
        push(self.redo_stack, cmd)

    proc redo(self):
        if len(self.redo_stack) == 0:
            return
        
        let last_idx = len(self.redo_stack) - 1
        let cmd = self.redo_stack[last_idx]
        
        # Pop from redo_stack
        let new_redo = []
        let i = 0
        while i < last_idx:
            push(new_redo, self.redo_stack[i])
            i = i + 1
        self.redo_stack = new_redo
        
        cmd.execute()
        push(self.undo_stack, cmd)
