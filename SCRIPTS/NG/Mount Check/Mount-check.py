#!/usr/bin/env python2

def check_fstab():

    import automount_check
    
    import os
    import popen2
    
    fname = "/etc/fstab"
    fd = open(fname, 'r')
    lines = fd.readlines()
    print "length of fstab file is " + `len(lines)`

    iter_cnt = 0
    for l1 in lines:
        if(l1.find("RAID") != -1):
            print "found RAID section"
            break
        else:
            iter_cnt += 1

    for l1 in lines[iter_cnt:]:
        try:
            if(l1.find("hard") != -1 or l1.find("panfs") != -1):
                dev_name = l1.split()[1]
                if dev_name == '/ms':
                    continue
                cmd = "ls -l " + dev_name + "/lost+found"
                (o1, s1, e1) = popen2.popen3(cmd)
                l2 = e1.readlines()
                l3 = l2[0]
                if l3.find("Permission denied") != -1 or l3.find("No such file or directory") != -1:
                    #
                    # check to see if the process to automount this device is still
                    # active. If it is, then skip, otherwise continue on automounting this device
                    #
                    if automount_check.check_am(dev_name) == 1:
                        print `dev_name` + ' is currently already attempting being mounted'
                        continue
                    umnt_cmd = "umount " + dev_name
                    (o2, s2, e2) = popen2.popen3(umnt_cmd)
                    o2_lines = o2.readlines()
                    print "Response from " + umnt_cmd
                    for o2_line in o2_lines:
                        print "\t" + o2_line
                        
                    mnt_cmd  =  "mount " + dev_name
                    (o2, s2, e2) = popen2.popen3(mnt_cmd)
                    print "Response from " + mnt_cmd
                    for o2_line in o2_lines:
                        print "\t" + o2_line
                    
##                elif l3.find("No such file or directory") != -1:
##                    umnt_cmd = "umount " + dev_name
##                    (o2, s2, e2) = popen2.popen3(umnt_cmd)
##                    o2_lines = o2.readlines()
##                    print "Response from " + umnt_cmd
##                    for o2_line in o2_lines:
##                        print "\t" + o2_line
                        
##                    mnt_cmd  =  "mount " + dev_name
##                    (o2, s2, e2) = popen2.popen3(mnt_cmd)
##                    print "Response from " + mnt_cmd
##                    for o2_line in o2_lines:
##                        print "\t" + o2_line
                
        except IndexError:
            i = 1
    
if __name__ == '__main__':

    status = check_fstab()
    