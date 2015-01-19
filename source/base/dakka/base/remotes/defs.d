/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2014 Richard Andrew Cattermole
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
module dakka.base.remotes.defs;
import dakka.base.defs;
import dakka.base.registration.actors;
import dakka.base.remotes.messages : utc0Time;
import vibe.d : msecs, Task, send, sleep;
import cerealed.decerealizer;

private shared {
	RemoteDirector director;

	shared static this() {
		director = cast(shared)new RemoteDirector();
	}
}

void setDirector(T : RemoteDirector)() {
	directory = cast(shared)new T();
}

void setDirector(RemoteDirector dir) {
	director = cast(shared)dir;
}

RemoteDirector getDirector() {
	synchronized {
		return cast()director;
	}
}

class RemoteDirector {
	import dakka.base.remotes.messages : DirectorCommunicationActions;
	alias DCA = DirectorCommunicationActions;


	private shared {
		Task[string] remoteConnections; // ThreadID[remoteAddressIdentifier]
		RemoteClassIdentifier[string] remoteClasses; // ClassIdentifier[uniqueInstanceIdentifier]
		string[][string][string] remoteClassInstances; // ClassIdentifier[][ClassType][remoteAddressIdentifier]
		string[][string] nodeCapabilities; //capability[][remoteAddressIdentifier]
		string[][string] localClasses; // ClassInstanceIdentifier[][ClassIdentifier]
		bool[string] addrLagCheckUse; // ShouldUse[remoteAddressIdentifier]
		ubyte[][string] retData; //data[UniqueAccessIdentifier]
	}

	bool validAddressIdentifier(string adder) {return (adder in remoteConnections) !is null;}
	bool validateBuildInfo(string) {return true;}
	bool validateClientCapabilities(string[]) {return true;}

	string[] allRemoteAddresses() { return cast()remoteConnections.keys; }

	void assign(string addr, Task task) {
		remoteConnections[addr] = cast(shared)task;
		addrLagCheckUse[addr] = true;
	}

	void unassign(string addr) {
		remoteConnections.remove(addr);
		nodeCapabilities.remove(addr);
		addrLagCheckUse.remove(addr);
	}

	bool shouldContinueUsingNode(string addr, ulong outBy) {
		bool ret = outBy < 10000;
		addrLagCheckUse[addr] = ret;
		return ret;
	}

	void receivedNodeCapabilities(string addr, string[] caps) {
		nodeCapabilities[addr] = cast(shared)caps;
	}


	bool canCreateRemotely(T : Actor)() {
		import std.algorithm : canFind;
		string[] required = capabilitiesRequired!T;

		foreach(addr, caps; nodeCapabilities) {

			bool good = true;
			foreach(cap; required) {
				if (!canFind(cast()caps, cap)) {
					good = false;
					break;
				}
			}
			if (good) {
				return true;
			}
		}

		return false;
	}

	bool preferablyCreateRemotely(T : Actor)() {
		// ugh our load balencing?
		return true;
	}

	string preferableRemoteNodeCreation(string identifier) {
		import std.algorithm : canFind;
		string[] required = capabilitiesRequired(identifier);
		string[] addrs;

		foreach(addr, caps; nodeCapabilities) {
			bool good = true;
			foreach(cap; required) {
				if (!canFind(cast(string[])caps, cap)) {
					good = false;
					break;
				}
			}
			if (good) {
				addrs ~= addr;
			}
		}

		if (addrs is null)
			return null;

		// ugh load balancing?

		// preferable vs not preferable?
		foreach(addr; addrs) {
			if ((cast()addrLagCheckUse).get(addr, true)) {
				return addr;
			}
		}

		return null;
	}


	string localActorCreate(string type) {
		import std.conv : to;
		if (type !in localClasses)
			localClasses[type] = [];

		string id = type ~ to!string(utc0Time) ~ to!string(localClasses[type].length);
		localClasses[type] ~= id;
		return id;
	}

	void localActorDies(string type, string identifier) {
		import std.algorithm : remove;
		remove((cast()localClasses[type]), identifier);
	}


	/**
	 * Received a request to create a class instance.
	 * 
	 * Returns:
	 * 		Class instance identifier
	 */
	string receivedCreateClass(string addr, string uid, string identifier, string parent) {
		import std.algorithm : canFind;
		string instance = null;

		// 	is parent not null?
		shared(Actor) parentRef;
		if (parent != "") {
			bool localInstance = false;
			string type;
			foreach(type2, instances; localClasses) {
				if (canFind(cast()instances, parent)) {
					localInstance = true;
					type = type2;
					break;
				}
			}
			//		is the parent a local class?
			if (localInstance) {
				parentRef = cast(shared)getInstance(parent).referenceOfActor;
				// 		else
			} else {
				//  		create a new one via actorOf (in some form)
				parentRef = cast(shared)new ActorRef!Actor(parent, addr);
			}
		}

		// can we create the actor on this system?
		if (canLocalCreate(identifier)) {
			// 		ask the registration system for actors to create it
			instance = createLocalActor(identifier).identifier;

			// else
		} else {
			//      return null
		}

		return instance;
	}

	void receivedEndClassCreate(string uid, string addr, string identifier, string parent) {
		remoteClasses[uid] = cast(shared)RemoteClassIdentifier(addr, identifier, parent);
	}

	bool receivedDeleteClass(string addr, string identifier) {
		getInstance(identifier).die();
		return true;
	}
	
	void receivedBlockingMethodCall(string uid, string addr, string identifier, string method, ubyte[] data) {
		callMethodOnActor(identifier, method, data, addr);
	}

	ubyte[] receivedNonBlockingMethodCall(string uid, string addr, string identifier, string method, ubyte[] data){
		return callMethodOnActor(identifier, method, data, addr);
	}
	
	void receivedClassReturn(string uid, ubyte[] data) {
		retData[uid] = cast(shared)data;
	}

	void receivedClassErrored(string identifier, string identifier2, string message) {
		getInstance(identifier).onChildError(identifier2 != "" ? getInstance(identifier2) : null, message);
	}

	void killConnection(string addr) {
		if (addr in remoteConnections)
			if ((cast()remoteConnections[addr]).running)
				remoteConnections[addr].send(DCA.GoDie);
	}

	@property string[] connections() {
		return remoteConnections.keys;
	}

	/**
	 * Blocking request to remote server to create a class
	 * 
	 * Returns:
	 * 		Class instance identifier
	 * 		Or null upon the connection ending.
	 */
	string createClass(string addr, string identifier, string parent) {
		import std.conv : to;

		if (addr in remoteConnections) {
			if ((cast()remoteConnections[addr]).running) {
				string uid = identifier ~ parent ~ to!string(utc0Time());

				remoteConnections[addr].send(DCA.CreateClass, uid, identifier, parent);

				while(uid !in remoteClasses && (cast()remoteConnections[addr]).running)
				{sleep(25.msecs());}

				if (uid in remoteClasses) {
					remoteClassInstances[addr][identifier] ~= remoteClasses[uid].identifier;
					return remoteClasses[uid].identifier;
				}
			}
		}
		return null;
	}

	void killClass(string addr, string type, string identifier) {
		import std.algorithm : filter;
		string[] newIds;
		foreach(v; remoteClassInstances[addr][type]) {
			if (v != identifier)
				newIds ~= v;
		}

		remoteClassInstances[addr][type] = cast(shared)newIds;
		remoteConnections[addr].send(DCA.DeleteClass, identifier);
	}

	void actorError(string addr, string identifier, string identifier2, string message) {
		remoteConnections[addr].send(DCA.ClassError, identifier, identifier2, message);
	}

	void callClassNonBlocking(string addr, string identifier, string methodName, ubyte[] data) {
		import std.conv : to;
		
		string uid = identifier ~ methodName ~ to!string(utc0Time());

		remoteConnections[addr].send(DCA.ClassCall, uid, identifier, methodName, cast(shared)data, false);
	}
	
	ubyte[] callClassBlocking(string addr, string identifier, string methodName, ubyte[] data){
		import std.conv : to;
		
		string uid = identifier ~ methodName ~ to!string(utc0Time());

		remoteConnections[addr].send(DCA.ClassCall, uid, identifier, methodName, cast(shared)data, true);
		
		while(uid !in retData && (cast()remoteConnections[addr]).running)
				{sleep(25.msecs());}
				
		ubyte[] ret = cast(ubyte[])retData[uid];
		
		retData.remove(uid);
			
		return ret;
	}

	void shutdownAllConnections() {
		import dakka.base.remotes.server_handler : shutdownListeners;
		import dakka.base.remotes.client_handler : stopAllConnections;
		shutdownListeners();
		stopAllConnections();
	}
}

struct RemoteClassIdentifier {
	string addr;
	string identifier;

	string parent;
}

/*
 * Init connections stuff
 */

struct DakkaRemoteServer {
	string hostname;
	string[] ips;
	ushort port;
}

struct DakkaServerSettings {
	ushort port;

	ulong lagMaxTime;
}

void clientConnect(DakkaRemoteServer[] servers...) {
	import dakka.base.remotes.client_handler;
	foreach(server; servers) {
		handleClientMessageServer(server);
	}
}

void serverStart(DakkaServerSettings[] servers...) {
	import dakka.base.remotes.server_handler;

	foreach(server; servers) {
		handleServerMessageServer(server);
	}
}

/*
 * Other
 */

struct DakkaActorRefWrapper {
	string identifier;
	string addr;
}

T grabActorFromData(T)(Decerealizer d, string addr=null) {
	DakkaActorRefWrapper wrapper = d.value!DakkaActorRefWrapper;

	if (wrapper.addr is null) {
		if (hasInstance(wrapper.identifier)) {
			return new ActorRef!T(cast(T)getInstance(wrapper.identifier), true);
		} else {
			return new ActorRef!T(wrapper.identifier, addr);
		}
	} else {
		return new ActorRef!T(wrapper.identifier, wrapper.addr);
	}
}