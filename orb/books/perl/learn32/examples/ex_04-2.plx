# ex_04-2# Learning Perl on Win32 Systems, Exercise 4.2print "What temperature is it? ";chomp($temperature = <STDIN>);if ($temperature > 75) {  print "Too hot!\n";} elsif ($temperature < 68) {  print "Too cold!\n";} else {  print "Just right!\n";}