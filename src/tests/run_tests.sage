from tests.test_model import test_model
from tests.test_layout import test_layout
from tests.test_commands import test_commands
from tests.test_audio import test_audio
from tests.test_utils import test_utils

proc main():
    print "==========================="
    print " Running SageMusic Tests"
    print "==========================="
    
    test_model()
    test_layout()
    test_commands()
    test_audio()
    test_utils()
    
    print "All tests passed successfully!"

main()
