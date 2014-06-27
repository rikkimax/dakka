module dakka.base.remotes.defs;
import dakka.base.defs;
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
		RemoteClassIdentifier[string] remoteClasses; // ClassIdentifier[instanceIdentifier]
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


	void assign(string addr, Task task) { remoteConnections[addr] = cast(shared)task; }
	void unassign(string addr) { remoteConnections.remove(addr); }
	bool shouldContinueUsingNode(string addr, ulong outBy) {return true;}


	bool canCreateRemotely(T : Actor)() {return false;} // TODO
	bool preferablyCreateRemotely(T : Actor)() {return false;} // TODO
	string preferableRemoteNodeCreation(string identifier) {return null;} // TODO


	string localActorCreate(string type) {return null;} // TODO
	void localActorDies(string type, string identifier) {} // TODO


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
			import dakka.base.remotes.messages : utc0Time;
			import std.conv : to;

			if (addr in remoteConnections) {
				if ((cast()remoteConnections[addr]).running) {
					string uid = identifier ~ parent ~ to!string(utc0Time());

					remoteConnections[addr].send(DCA.CreateClass, uid, identifier, parent);

					// TODO: get the class instance from this, return it.
					while(uid !in remoteClasses && (cast()remoteConnections[addr]).running)
					{sleep(25.msecs());}

					if (uid in remoteClasses)
						return remoteClasses[uid].identifier;
				}
			}
			return null;
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