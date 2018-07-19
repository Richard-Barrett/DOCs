#!/usr/bin/env python2

"""
System to determine nodes which do not have jobs running on them.
If there are no idle nodes, then build a list of all nodes available
and return to the user.
"""

import os
import sys
import queues

def free_nodes():
    """
    Routine to determine nodes which have no jobs assigned to them at this time
    """
    free_list = []
    pbs = queues.Pbs()
    for node in pbs.getNodes():
        if node.__dict__.has_key('jobs'):
            continue
        if node.state == 'free':
            free_list.append(node.name)
    #
    # if there are no free nodes available, then create list of all nodes and
    # return this list to the user.
    #
    if len(free_list) == 0:
        for node in pbs.getNodes():
            free_list.append(node.name)
    
    return free_list

if __name__ == '__main__':
    free_list = free_nodes()
    for node in free_list:
        print '%12s' % (node)