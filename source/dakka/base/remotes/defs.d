module dakka.base.remotes.defs;
import dakka.base.defs;
import dakka.base.registration.actors;
import dakka.base.remotes.messages : utc0Time;
import vibe.d : msecs, Task, send, sleep;

private __gshared {
	RemoteDirector director;
}

void setDirector(T : RemoteDirector)() {
	directory = new T();
}

void setDirector(RemoteDirector dir) {
	director = dir;
}

RemoteDirector getDirector() {
	synchronized {
		return director;
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
	}

	bool validAddressIdentifier(string adder) {return (adder in remoteConnections) !is null;}

	this() {
		validateBuildInfo = &buildInfoValidator;
		validateClientCapabilities = &clientCapabilitiesValidator;
	}

	bool delegate(string) validateBuildInfo;
	bool delegate(string[]) validateClientCapabilities;

	bool buildInfoValidator(string) {return true;}
	bool clientCapabilitiesValidator(string[]) {return true;}


	void assign(string addr, Task task) {
		remoteConnections[addr] = cast(shared)task;
	}

	void unassign(string addr) {
		remoteConnections.remove(addr);
		nodeCapabilities.remove(addr);
	}

	bool shouldContinueUsingNode(string addr, ulong outBy) {
		return true;
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
				if (!canFind(cast()caps, cap)) {
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


		// a crude form of load balancing

		size_t less = size_t.max;
		string addr2;

		foreach(addr, values; remoteClassInstances) {
			if (values.get(identifier, []).length < less) {
				less = values.length;
				addr2 = addr;
			}
		}
		return addr2;
	}


	string localActorCreate(string type) {
		import std.conv : to;
		string id = type ~ to!string(utc0Time) ~ to!string(localClasses[type].length);
		localClasses[type] ~= id;
		return id;
	}

	void localActorDies(string type, string identifier) {
		import std.algorithm : remove;
		remove((cast()localClasses[type]), identifier);
	}


	/**
	 * TODO
	 * Received a request to create a class instance.
	 * 
	 * Returns:
	 * 		Class instance identifier
	 */
	string receivedCreateClass(string addr, string uid, string identifier, string parent) {
		string instance = null;

		// 	is parent not null?
		//		is the parent a local class?
		//  		create an ActorRef for it.
		// 		else
		//  		create a new one via actorOf (in some form)

		// can we create the actor on this system?
		// 		ask the registration system for actors to create it
		// 		return its unique identifier		
		// else
		//      return null

		// in new thread call onStart!
		// also register it via localActorCreate

		return instance;
	}

	final {
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

					// TODO: get the class instance from this, return it.
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
			import std.algorithm : remove;
			// TODO: something
			remove((cast()remoteClassInstances[addr][type]), identifier);
		}

		void callClassBlocking(string identifier, ubyte[] data){}//TODO
		ubyte[] callClassNonBlocking(string identifier, ubyte[] data){return null;}//TODO
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