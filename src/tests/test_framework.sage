import sys
import strings

proc assert_eq(expected, actual, msg):
    if expected != actual:
        print "FAIL: " + msg
        print "  Expected: " + str(expected)
        print "  Actual:   " + str(actual)
        sys.exit(1)
    else:
        print "PASS: " + msg
        
proc assert_true(condition, msg):
    if not condition:
        print "FAIL: " + msg
        sys.exit(1)
    else:
        print "PASS: " + msg
