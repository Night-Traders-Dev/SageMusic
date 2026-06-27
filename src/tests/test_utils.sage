from tests.test_framework import assert_eq, assert_true
from utils.helpers import get_safe_part, get_safe_measure
from model.model import Score, Part, Measure

proc test_utils():
    print "--- Testing Utils ---"
    
    let score = Score("Test")
    let p1 = get_safe_part(score, 0)
    assert_true(p1 == nil, "Empty score returns nil part")
    
    let p2 = Part("P1")
    score.add_part(p2)
    let p3 = get_safe_part(score, 0)
    assert_eq("P1", p3.name, "Valid part returned")
    
    let m1 = get_safe_measure(p3, 0)
    assert_true(m1 == nil, "Empty part returns nil measure")
    
    let m2 = Measure()
    p3.add_measure(m2)
    let m3 = get_safe_measure(p3, 0)
    assert_true(m3 != nil, "Valid measure returned")
    
    print "Utils tests passed.\n"
