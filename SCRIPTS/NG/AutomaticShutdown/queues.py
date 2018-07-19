#!/usr/bin/env python2
"""
Module queues.py

This module provides pythonic access to the information provided by the PBS
queue manager, qmgr.  To accomplish this, it obtains an initial state from the
queue manager when the Pbs class is instantiated.

"""

import os

class AbstractException(Exception):
    """
    Raise this exception when an attempt is made to instantiate an abstract class.
    """
    pass

# Define useful classes
class Pbs_Resource:
    """
    Abstract base class for all PBS resource types

    PBS resources are nodes, queues and servers
    .  This base class defines
    methods useful on any type of PBS node.  Functions specific to the type
    of node defined can be found in subclasses of this class.
    """
    def __init__(self, name, strings):
        if not self.__dict__.has_key('type'):
            raise AbstractException('Subclasses of Pbs_Resource must specify type')
        self.name = name
        for string in strings[1:]:
            if string.find('\t') == 0:
                string = string.split('\t')[1]
                try:
                    name, value = string.split(' = ', 1)
                    self.__dict__[name] = value
                except:
                    print 'Failed to unpack string "%s"' % string
            else:
                self.__dict__[name] += string.strip()

    def qshow(self):
        pass

    def getName(self):
        return self.name

    def showName(self):
        print '%s :  %s' % (self.type, self.name)

    def showEntry(self, entry):
        if self.__dict__.has_key(entry):
            print '   %s :  %s' % (entry, self.__dict__[entry])

    def show(self):
        self.showName()
        for key in self.__dict__.keys():
            self.showEntry(key)

class Server(Pbs_Resource):
    def __init__(self, name, strings):
        self.type = 'server'
        Pbs_Resource.__init__(self, name, strings)

class Queue(Pbs_Resource):
    def __init__(self, name, strings):
        self.from_route_only = False
        self.started = False
        self.enabled = False
        self.queue_type = None
        self.type = 'queue'
        Pbs_Resource.__init__(self, name, strings)

    def qshow(self):
        print '%s :  %s' % (self.type, self.name)
        self.showEntry('queue_type')
        self.showEntry('started')
        self.showEntry('enabled')
        self.showEntry('route_destinations')
        self.showEntry('from_route_only')

    def isStarted(self):
        return self.started == 'True'

    def isEnabled(self):
        return self.enabled == 'True'

    def fromRouteOnly(self):
        return self.from_route_only == 'True'

    def queueType(self):
        return self.queue_type

    def route(self):
        if self.queueType() == 'Route':
            return self.route_destinations
        else:
            return None

class Node(Pbs_Resource):
    def __init__(self, name, strings):
        self.type = 'node'
        Pbs_Resource.__init__(self, name, strings)

    def qshow(self):
        self.showName()
        self.showEntry('queue')

    def getQueue(self):
        if self.__dict__.has_key('queue'):
            return self.queue
        else:
            return None

class Pbs:
    def __init__(self):
        self.FindServers()
        self.FindQueues()
        self.FindNodes()

    def getServers(self):
        return self.servers

    def getQueues(self):
        return self.queues

    def getNodes(self):
        return self.nodes

    def getServerByName(self, name):
        for server in self.servers:
            if server.getName() == name:
                return server
        return None

    def getQueueByName(self, name):
        for queue in self.queues:
            if queue.getName() == name:
                return queue
        return None

    def getNodeByName(self, name):
        for node in self.nodes:
            if node.getName() == name:
                return node
        return None

    def Request(self, query):
        """
        Sends an information request to the queue manager.
        
        Send a query to the queue manager generically.  The result is a list of
        the query results.  Before sending a request, set all servers, queues,
        and nodes active so we can find them.

        """
        # Submit the request to qmgr
        instream, outstream = os.popen2('/usr/pbs/bin/qmgr')
        instream.write('active server @active\n')
        instream.write('active queue @active\n')
        instream.write('active node @active\n')
        instream.write('%s\n' % (query,))
        instream.write('exit')
        instream.close()
        result = outstream.read().splitlines()
        outstream.close()
        return result

    def FindServers(self):
        self.servers = []
        result = self.Request('list server')
        for lineNo in range(len(result)):
            # If the line starts with 'Server', we've found a server name
            if result[lineNo].find('Server') == 0:
                name = result[lineNo].split(' ')[1]
                strings = []
                while result[lineNo] != '':
                    strings.append(result[lineNo])
                    lineNo += 1
                self.servers.append(Server(name, strings))

    def FindQueues(self):
        self.queues = []
        result = self.Request('list queue')
        for lineNo in range(len(result)):
            # If the line starts with 'Queue', we've found a queue name
            if result[lineNo].find('Queue') == 0:
                name = result[lineNo].split(' ')[1]
                strings = []
                while result[lineNo] != '':
                    strings.append(result[lineNo])
                    lineNo += 1
                self.queues.append(Queue(name, strings))

    def FindNodes(self):
        self.nodes = []
        result = self.Request('list node')
        for lineNo in range(len(result)):
            # If the line starts with 'Node', we've found a node name
            if result[lineNo].find('Node') == 0:
                name = result[lineNo].split(' ')[1]
                strings = []
                while result[lineNo] != '':
                    strings.append(result[lineNo])
                    lineNo += 1
                self.nodes.append(Node(name, strings))

def qshow():
    pbs = Pbs()
    for queue in pbs.getQueues():
        if queue.isStarted() and queue.isEnabled():
            if queue.queueType() == 'Execution':
                if not queue.fromRouteOnly():
                    print '%s: ' % queue.getName()
                    for node in pbs.getNodes():
                        if node.getQueue() == queue.getName():
                            print '   %s' % node.getName()
                            if node.__dict__.has_key('jobs'):
                                print '      Jobs:', node.jobs

            elif queue.queueType() == 'Route':
                route_queues = queue.route().split(',')
                print '%s: ' % queue.getName()
                for q_name in route_queues:
                    q = pbs.getQueueByName(q_name)
                    if q == None:
                        print 'Configuration error: queue %s currently has queue' % queue.getName(),
                        print '%s as a destination queue, but there is no queue %s' % (q, q)
                        break
                    if q.isStarted() and q.isEnabled():
                        queueOnNode = False
                        for node in pbs.getNodes():
                            if node.getQueue() == q.getName():
                                queueOnNode = True
                                print '   %s' % node.getName()
                                if node.__dict__.has_key('jobs'):
                                    print '      Jobs:', node.jobs
                        if not queueOnNode:
                            print 'Configuration error: queue %s is a route queue destination' % q.getName(),
                            print 'but no node is configured to accept jobs from that queue'
                    else:
                        print 'Configuration error: queue', q.getName(), 'is either not started or not enabled'

if __name__ == '__main__':
    qshow()