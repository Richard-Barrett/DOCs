#!/usr/bin/env python2

def PowerTower_Outlet():

    '''
    This routine defines the outlets for each powertower/rack combination.
    '''

    PT_dict = {}

    # Define outlets for Cabinet 1
    # Currently there is no Power Towers in this cabinet

    # Define outlets for Cabinet 2
    # Currently there is no Power Towers in this cabinet

    # Define outlets for Cabinet 3
    PT_dict['gandalf1'] = ('pt3', ('.A1', '.A2', '.A3', '.A4', '.B2', '.B3', '.B4'))
    PT_dict['gandalf2'] = ('pt3', ('.A6', '.A7', '.A8', '.B5', '.B6', '.B7', '.B8'))
    PT_dict['gandalf3'] = ('pt3', ('.B13', '.B14', '.B15'))
    PT_dict['gandalf4'] = ('pt3', ('.A13',))

    # Define outlets for Cabinet 4
    PT_dict['gandalf5'] = ('pt4', ('.A1', '.A2', '.A3', '.A4', '.B2', '.B3', '.B4'))
    PT_dict['gandalf6'] = ('pt4', ('.A5', '.A6', '.A7', '.B5', '.B6', '.B7', '.B8'))
    PT_dict['gandalf7'] = ('pt4', ('.A8', '.A9', '.A10', '.A11', '.B9', '.B10', '.B11'))
    PT_dict['gandalf8'] = ('pt4', ('.A12', '.A13', '.A14', '.A15', '.B12', '.B13', '.B14'))
    
    # Define outlets for Cabinet 5
    PT_dict['frodo1' ] = ('pt5', ('.A1',))
    PT_dict['frodo2' ] = ('pt5', ('.B2',))
    PT_dict['frodo3' ] = ('pt5', ('.A2',))
    PT_dict['frodo4' ] = ('pt5', ('.B3',))
    PT_dict['frodo5' ] = ('pt5', ('.A3',))
    PT_dict['frodo6' ] = ('pt5', ('.B4',))
    PT_dict['frodo7' ] = ('pt5', ('.A4',))
    PT_dict['frodo8' ] = ('pt5', ('.B5',))
    PT_dict['frodo9' ] = ('pt5', ('.A5',))
    PT_dict['frodo10'] = ('pt5', ('.B6',))
    PT_dict['frodo11'] = ('pt5', ('.A14',))
    PT_dict['frodo12'] = ('pt5', ('.B14',))
    PT_dict['frodo13'] = ('pt5', ('.A15',))
    PT_dict['frodo14'] = ('pt5', ('.B15',))
    PT_dict['frodo15'] = ('pt5', ('.A16',))
    PT_dict['frodo16'] = ('pt5', ('.B16',))
    
    # Define outlets for Cabinet 6
    PT_dict['frodo17'] = ('pt6', ('.A1',))
    PT_dict['frodo18'] = ('pt6', ('.B2',))
    PT_dict['frodo19'] = ('pt6', ('.A2',))
    PT_dict['frodo20'] = ('pt6', ('.B3',))
    PT_dict['frodo21'] = ('pt6', ('.A3',))
    PT_dict['frodo22'] = ('pt6', ('.B4',))
    PT_dict['frodo23'] = ('pt6', ('.A4',))
    PT_dict['frodo24'] = ('pt6', ('.B5',))
    PT_dict['frodo25'] = ('pt6', ('.A5',))
    PT_dict['frodo26'] = ('pt6', ('.B6',))
    PT_dict['frodo27'] = ('pt6', ('.A14',))
    PT_dict['frodo28'] = ('pt6', ('.B14',))
    PT_dict['frodo29'] = ('pt6', ('.A15',))
    PT_dict['frodo30'] = ('pt6', ('.B15',))
    PT_dict['frodo31'] = ('pt6', ('.A16',))
    PT_dict['frodo32'] = ('pt6', ('.B16',))

    # Define outlets for Cabinet 7
    PT_dict['frodo33'] = ('pt7', ('.A1',))
    PT_dict['frodo34'] = ('pt7', ('.B2',))
    PT_dict['frodo35'] = ('pt7', ('.A2',))
    PT_dict['frodo36'] = ('pt7', ('.B3',))
    PT_dict['frodo37'] = ('pt7', ('.A3',))
    PT_dict['frodo38'] = ('pt7', ('.B4',))
    PT_dict['frodo39'] = ('pt7', ('.A4',))
    PT_dict['frodo40'] = ('pt7', ('.B5',))
    PT_dict['frodo41'] = ('pt7', ('.A5',))

    # Define outlets for Cabinet 8
    PT_dict['gandalf10'] = ('pt8', ('.A14', '.A15', '.A16'))
    PT_dict['gandalf11'] = ('pt8', ('.A11', '.A12', '.A13'))
    PT_dict['gandalf12'] = ('pt8', ('.A1',))

    # Define outlets for Cabinet 9
    PT_dict['MYRINET'] = ('pt9', ('.A1',))
    PT_dict['Force10'] = ('pt9', ('.A2', '.A3'))
    PT_dict['Pan3'   ] = ('pt9', ('.A14', '.B14'))
    PT_dict['Pan2'   ] = ('pt9', ('.A15', '.B15'))
    PT_dict['Pan1'   ] = ('pt9', ('.A16', '.B16'))

    # Define outlets for Cabinet 10
    PT_dict['KVM'    ] = ('pt10', ('.B1',))
    PT_dict['gandalf13'] = ('pt10', ('.A1',))
    PT_dict['gandalf14'] = ('pt10', ('.B2',))
    PT_dict['gandalf15'] = ('pt10', ('.A2',))
    PT_dict['gandalf16'] = ('pt10', ('.B3',))
    PT_dict['gandalf17'] = ('pt10', ('.A3',))
    PT_dict['gandalf18'] = ('pt10', ('.B4',))
    PT_dict['gandalf20'] = ('pt10', ('.B14',))
    PT_dict['gandalf21'] = ('pt10', ('.A15',))
    PT_dict['gandalf22'] = ('pt10', ('.B15',))
    PT_dict['gandalf23'] = ('pt10', ('.A15',))
    PT_dict['gandalf24'] = ('pt10', ('.B16',))

    # Define outlets for Cabinet 11
    PT_dict['KVM'      ] = ('pt11', ('.B1',))
    PT_dict['gandalf25'] = ('pt11', ('.A1',))
    PT_dict['gandalf26'] = ('pt11', ('.B2',))
    PT_dict['gandalf27'] = ('pt11', ('.A2',))
    PT_dict['gandalf28'] = ('pt11', ('.B3',))
    PT_dict['gandalf29'] = ('pt11', ('.A3',))
    PT_dict['gandalf30'] = ('pt11', ('.B4',))
    PT_dict['gandalf31'] = ('pt11', ('.A14',))
    PT_dict['gandalf32'] = ('pt11', ('.B14',))
    PT_dict['gandalf33'] = ('pt11', ('.A15',))
    PT_dict['gandalf34'] = ('pt11', ('.B15',))
    PT_dict['gandalf35'] = ('pt11', ('.A16',))
    PT_dict['gandalf40'] = ('pt11', ('.B16',))

    # Define outlets for Cabinet 12
    # This cabinet currently does not have any Power Towers associated

    # Define outlets for Cabinet 13
    PT_dict['orc1'     ] = ('pt13', ('.A1',))
    PT_dict['gandalf38'] = ('pt13', ('.A3',))
    PT_dict['gandalf39'] = ('pt13', ('.A7',))
    PT_dict['gandalf9' ] = ('pt13', ('.A8', '.A10', '.A11', '.A12', '.B12', '.B13', '.B14'))
    PT_dict['backup'   ] = ('pt13', ('.B2', '.B3'))
    PT_dict['gandalf37'] = ('pt13', ('.B4', '.B5'))
    PT_dict['orc2'     ] = ('pt13', ('.B6',))
    PT_dict['Legolas'  ] = ('pt13', ('.A13', '.A15', '.A16', '.B15', '.B16'))
    
    # Define outlets for Cabinet 14
    PT_dict['frodo42'] = ('pt14', ('.A1', '.A2'))
    PT_dict['frodo43'] = ('pt14', ('.B1', '.B2'))
    PT_dict['frodo44'] = ('pt14', ('.A3', '.A4'))
    PT_dict['frodo45'] = ('pt14', ('.B3', '.B4'))

    return PT_dict

if __name__ == '__main__':

    PT_d = PowerTower_Outlet()

    for d in PT_d.items():
        Cabinet = d[1][0]
        try:
            Outlet  = d[1][1]
        except:
            print 'Unable to obtain outlets for ' + `Cabinet`
            
        print 'Node Name=' + d[0] + ' is on oulet ' + `Outlet` + ' in cabinet ' + Cabinet
