#!/usr/bin/env python2

def check_am( in_device ):

    import os
    import popen2
    import sys
    
    cmd = 'ps -ef'
    (o2, s2, e2) = popen2.popen3(cmd)
    o2_lines = o2.readlines()

    am = 0
    
    for o2_line in o2_lines:
        o2_1 = o2_line.split()
        if o2_1[7].startswith('mount'):
            o2_2 = o2_1[9].split(':')
            if o2_2[1][0:5] == in_device[0:5]:
                am = 1
                break

    o2.close()
    return am

if __name__ == '__main__':

    print check_am('/u/s018')
    
