from tests.test_framework import assert_eq, assert_true
from command.command import CommandHistory, AddElementCommand, DeleteElementCommand
from model.model import Note, Measure, Voice, Part

proc test_commands():
    print "--- Testing Commands ---"
    
    let history = CommandHistory()
    let m = Measure()
    let v = m.get_voice(0)
    
    let note = Note("D4", 0.25)
    
    let add_cmd = AddElementCommand(v, note)
    history.execute(add_cmd)
    
    assert_eq(1, len(v.elements), "Note added via command")
    assert_eq("D4", v.elements[0].pitch, "Pitch is correct")
    
    history.undo()
    assert_eq(0, len(v.elements), "Note removed via undo")
    
    history.redo()
    assert_eq(1, len(v.elements), "Note restored via redo")
    
    let del_cmd = DeleteElementCommand(v, note)
    history.execute(del_cmd)
    assert_eq(0, len(v.elements), "Note deleted via command")
    
    history.undo()
    assert_eq(1, len(v.elements), "Note restored via undo of delete")
    
    print "Command tests passed.\n"
