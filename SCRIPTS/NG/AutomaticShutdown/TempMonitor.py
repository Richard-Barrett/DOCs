#!/usr/bin/env python2

"""This program is used to monitor the temperature of the cluster
computer room. This program was written assuming that it is run as
a process in the root account (system administrator). It is recommended
that this program be initiated as part of the boot sequence so that
monitoring can occur at all times.

The monitoring process consists of three phases.

The first phase is that if the temperature reaches and exceeds 80
degrees farenheit and stays below 85 degrees fahrenheit for a
period of 5 minutes, then all the nodes which are idle, will be
shutdown and then powered off.

During the second phase, if the temperature continues to rise
above 85 degrees fahrenheit and remains below 90 degrees fahrenheit
for a period of 5 minutes, then additional nodes will be shutdown and
powered off.

During the third phase, if the temperature exceeds 90 degrees fahrenheit
for a period of 5 minutes, then then entire cluster will be shutdown
and powered off. Exceptions to this are that aragorn, and the four
lightsaber machines will not be shutdown or powered off."""

def connect_2_PowerTower(HOST, lgFile):
    """
    This routine is used to 'login' to the powertower designated
    by the argument HOST.
    The value returned from this function will either be the instance
    of the connection (if successful) or the value None if unsuccessful.
    """
    username = 'admn\n'
    password = 'admn\n'
    try:
        tn   = Telnet(HOST)
    except:
        #
        # If unable to connect to this HOST, then issue a warning
        # to the user and return None. This will be 'caught' in the
        # caller, so no attempt will be made to send command to this
        # power tower
        #
        lgFile.write('\texception occurred when attempting to connect to ' + HOST + '\n')
        tn = None
        return tn
    tn.read_until("Username: ")
    tn.write(username)
    tn.read_until("Password: ")
    tn.write(password)
    tn.read_until("Sentry: ")

    return tn

def ShutDown_Node( node ):
    """
    This routine is used to shutdown the node using the /sbin/init 0 command.
    The shutdown is initiated via the rsh program.
    """

    import os
    
    cmd = 'rsh ' + `node` + ' /sbin/init 0'
    (child_stdin, child_stdout, child_stderr) = os.popen3(cmd)
    err_line = child_stderr.readlines()
    if len(err_line) != 0:
        return 0
    out_line = child_stdout.readlines()

    try:
        child_stdin.close()
    except:
        pass
    try:
        child_stdout.close()
    except:
        pass
    try:
        child_stderr.close()
    except:
        pass

    return 1

def turn_off_nodes(available_nodes, PT, lgFile):
    """
    This routine is used when the tempature is between 80 degrees fahrenheit and
    85 degrees fahrenheit. When the tempature reaches these levels it is desired
    that any idle machines (frodos) will be powered off.
    """
    from time import sleep
    
    lgFile.write('turn_off_nodes\n')
    #
    # First manually shutdown each node individually.
    #
    for node in available_nodes:
        host = PT[node][0]
        status = ShutDown_Node( node )
        if status:
            lgFile.write('\tSuccessfully shutdown ' + `node` + ':' + `status` + '\n')
        else:
            lgFile.write('\tUnsuccessfully shutdown ' + `node` + ':' + `status` + '\n')
    #
    # Sleep for 5 minutes, to provide time for the node to shutdown cleanly.
    #
    time.sleep(300)
    #
    # Now, for each node determine which outlet, on which Power Tower this node
    # is connected to and power it down.
    #
    for node in available_nodes:
        host = PT[node][0]
        #
        # Connect to Power Tower in which the equipment is plugged into
        #
        tower_id = connect_2_PowerTower(host, lgFile)
        if tower_id != None:
            outlets = PT[node][1]
            #
            # Write to the logfile information on which node was powered off.
            lgFile.write('\tTurn off ' + node + ', ' + host + ', Outlet(s) ')
                
            for outlet in outlets:
                turn_off_outlet(tower_id, outlet, lgFile)
            lgFile.write('\n')
            tower_id.write('LOGOUT\n')
        
def turn_off_all(PT, lgFile):
    """
    This routine is used when the tempature exceeds 90 degrees fahrenheit.
    When the tempature reaches this level, then something terrible has happened
    and all machines will be powered off.
    """
    import os
    from time import sleep
    #
    # Siggy will need to modify the path provided in the following line of code
    # to properly point to the location where the shutdown scripts are located
    #
    os.environ['PATH'] = os.environ['PATH'] + ':/u/s018/bbb187/TempMonitor/scripts'
    #
    # Setup to run the script which will gracefully shutdown all the nodes in
    # the area 1 cluster room.
    #
    cmd = 'SHUTDOWN-MASTER'
    a = os.spawnlpe(os.P_NOWAIT, cmd, '', os.environ)
    lgFile.write('\tos.spawnvpe SHUTDOWN-MASTER response -> ', a)
    #
    # According to Siggy, he desires for this process to sleep for 10 minutes to
    # allow time for the machines to gracefully shutdown prior to removal of the
    # power. If the machines have not gracefully shutdown by this time, then removal
    # of the power will indeed shut the nodes down. Siggy takes full responsibility
    # for the outcome of this decision. The sleep function take the time to sleep
    # in units of seconds, so 600 seconds equates to 10 minutes.
    #
    sleep(600)
    #
    # At this point, we have awoken from our nap, so it's time to turn off the
    # power to all the cabinets.
    # First we go through and turn off all the nodes defined in the text file
    # provided by Siggy for the nodes. This script will attempt to turn off
    # the power to each of these devices one at a time.
    #
    node_list = open('/etc/beowulf/bcs/allnodes', 'r')
    nodes     = node_list.readlines()
    PT        = PowerTower_Outlet()
    for node in nodes:
        node = node[0:len(node)-1]
        lgFile.write(node)
        try:
            if PT.has_key(node) == 1:
                host = PT[node][0]
                outlets = PT[node][1]
                lgFile.write(host)
                for outlet in outlets:
                    lgFile.write(outlet)
                lgFile.write('\n')
        except:
            lgFile.write('\tUnable to access ' + node + '\n')

    node_list.close()
    #
    # Second we go through and turn off all the mass storage devices defined
    # in the text file provided by Siggy for the nodes. This script will
    # attempt to turn off the power to each of these devices one at a time.
    #
    gand_list = open('/etc/beowulf/bcs/gand-list', 'r')
    gands     = gand_list.readlines()
    for gand in gands:
        gand = gand[0:len(gand)-1]
        lgFile.write(gand)
        try:
            if PT.has_key(gand) == 1:
                host = PT[gand][0]
                outlets = PT[gand][1]
                lgFile.write(host)
                for outlet in outlets:
                    lgFile.write(outlet)
                lgFile.write('\n')
        except:
            lgFile.write('Unable to access ' + gand + '\n')
    
    gand_list.close()
    
def turn_off_outlet(tn, outlet, lgFile):
    """
    This routine will turn off the outlet identified by the argument outlet.
    The powertower which this outlet is a part of is identified by the argument
    tn
    """
    lgFile.write(outlet)
##    tn.write('off ' + outlet + '\n')
##    response = tn.read_until("Sentry: ")
             
def get_Temp(tn):
    """
    This function will parse the response back from the envmon command to
    determine the tempature sensed by the enviromental monitor.
    This only obtains the information connected to the A1 sensor.
    The tempature returned is in degrees celsius
    """
    tn.write('envmon\n')
    a = tn.read_until("Sentry: ")
    parts = a.split()
    i1 = parts.index('Temp_Humid_Sensor_A1')
    Temp = float(parts[i1+1])
    Temp_Class = parts[i1+3]
    
    return Temp

def Celsius_2_Fahrenheit(Celsius):
    """
    This routine converts from celsius to fahrenheit
    """
    return(Celsius*(9.0/5.0)+32.0)

if __name__ == '__main__':

    #  The tempature monitoring is accomplished via the network connection
    #  to a particular PowerTower,which is monitored every 10 minutes, where
    #  the temperature is acquired and converted from degrees celsius to degrees
    #  fahrenheit.
    
    import getpass
    import sys
    import time
    import os
    from free_nodes import free_nodes
    from fpformat   import fix
    from telnetlib  import Telnet
    from PowerTower_Outlet import PowerTower_Outlet
    #
    # Initialization section
    # Initialize the counters for each of the temperature band
    # sections.
    #
    icnt_0       = 0
    icnt_1       = 0
    icnt_2       = 0
    icnt_3       = 0
    #
    # Initialize the maximum number of minutes each section the
    # temperature is allowed to stay in before an 'alarm' is
    # sounded (not really), and action is initiated to turn
    # off equipment to slow the temperature rise in the computer room
    #
    max_region_1 = 1 #sys.maxint
    max_region_2 = sys.maxint
    max_region_3 = sys.maxint
    #
    # Create a logfile name which consists of the following form:
    #   <a>_<b>_<d>_<Y>.<H>_<M>
    # where these fields represent:
    #   <a> -> <abbreviated weekday name>
    #   <b> -> <abbreviated month name>
    #   <d> -> <Day of the month as a decimal number>
    #   <Y> -> <Year with century as a decimal number>
    #   <H> -> <Hour (24-hour clock) as a decimal number [00,23]>
    #   <M> -> <Minute as a decimal number [00,59]>

    Current_Day = int(time.strftime('%H'))
    lgName = time.strftime('%a_%b_%d_%Y.%H_%M') + '.log'

    # The logfile will be opened in a directory under the users home directory:
    #   $HOME/TempMonitor/logs
    
    lgFile = open(os.path.join(os.getenv('PWD'), 'logs/' + lgName), 'w', 0)

    EnvMonHOST = 'pt10' # The environmental monitor is connected to cabinet 13.

    tn = connect_2_PowerTower(EnvMonHOST, lgFile)

    # obtain the dictionary containing list of units and which PT/outlet they are
    # paired with
    
    PT = PowerTower_Outlet()
    #
    # Get the initial temperature and convert it from degrees celsius to degrees Fahrenheit
    #
    Temp_F = Celsius_2_Fahrenheit(get_Temp(tn))
    #
    # infinite loop, which will monitor the temperature every 60 seconds.
    # if the temperature stays at an level which is considered problematic, and stays there for
    # a predetermined amount of time, then this code will take pre-determined action.
    #
    while 1:
        #
        # Write to the logfile the current temperature and time
        #
        lgFile.write('Tempature is ' + fix(Temp_F, 4) + ' at time ' + time.strftime('%a_%b_%d_%Y.%H_%M') + '\n')
        print 'Tempature is ' + fix(Temp_F, 4) + ' at time ' + time.strftime('%a_%b_%d_%Y.%H_%M')
        if Temp_F <  80.0:
            #
            # This part of the if statement block is when the temperature is below
            # the lower limit of unsafe temperatures. At this point just increment
            # the region specific counter and continue on with the loop
            #
            Safe_Temperature = 1
            icnt_1           = 0 # reset region 1 counter
            icnt_2           = 0 # reset region 2 counter
            icnt_3           = 0 # reset region 3 counter
            if(icnt_0 > sys.maxint/2):
                icnt_0 = 1
            else:
                icnt_0 += 1
        elif Temp_F >= 80.0 and Temp_F < 85.0:
            #
            # This part of the if statement block is reached when the temperature
            # reaches the first 'unsafe' temperature region (region 1). At this
            # point increment the counter and determine if it is time to start
            # turning off equipment.
            #
            Safe_Temperature = 2
            icnt_0  = 0        # reset region 0
            icnt_1 += 1        # increment region 1
            icnt_2  = 0        # reset region 2
            if(icnt_1 >= max_region_1):
                available_nodes = free_nodes()
                turn_off_nodes(available_nodes, PT, lgFile)
            else:
                lgFile.write('ST='+`Safe_Temperature`+' counter='+`icnt_1`+'\n')
                
        elif Temp_F >= 85.0 and Temp_F < 90.0:
            #
            # This part of the if statement block is reached when the temperature
            # reaches the second 'unsafe' temperature region (region 2). At this
            # point increment the counter and determine if it is time to turn off
            # more equipment.
            #
            Safe_Temperature = 3
            icnt_2 += 1
            icnt_3  = 0
            if(icnt_2 >= max_region_2):
                available_nodes = free_nodes()
                turn_off_nodes(available_nodes, PT, lgFile)
                
        elif Temp_F >= 90.0:
            #
            # This part of the if statement block is reached when the temperature
            # reaches the last 'unsafe' temperature region (region 2). At this
            # point increment the counter and determine if it is time to turn off
            # all equipment.
            #
            icnt_3 += 1
            if(icnt_3 >= max_region_3):
                Safe_Temperature = 0
                turn_off_all(PT, lgFile)
                break
        #
        # go to sleep for 1 minute and recheck.
        #
        time.sleep(60)
        #
        # Determine if we have changed hours, and if we have, close the existing
        # logfile and open up a new one.
        #
        if Current_Day != int(time.strftime('%H')):
            Current_Day = int(time.strftime('%H'))
            lgFile.close()
            lgName = time.strftime('%a_%b_%d_%Y.%H_%M') + '.log'
            lgFile = open(os.path.join(os.getenv('PWD'), 'logs/' + lgName), 'w', 0)
            
        Temp = get_Temp(tn)
        Temp_F = Celsius_2_Fahrenheit(Temp)
    else:
        lgFile.write('Tempature is ' + fix(Temp_F, 4) + ' and is not')
        lgFile.write('within the safe range\n')

    #
    # This signafies the end of the loop. This should only occur when the temperature
    # exceeds 90 degrees Fahrenheit.
    
    lgFile.close()
    