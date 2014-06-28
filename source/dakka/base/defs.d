﻿module dakka.base.defs;
import dakka.base.impl.defs;
//import dakka.base.central;

private {
	static if (__traits(compiles, import("BuildIdentifier.txt"))) {
		__gshared string buildText = import("BuildIdentifier.txt");
	} else {
		__gshared string buildText = "DakkaBuild#" ~ __TIMESTAMP__;
	}
}

void assignBuildTitle(string text) {
	buildText = text;
}

string getBuildTitle() {
	return buildText;
}

class Actor {
	import vibe.d : runTask;
	import binary.pack;
	
	shared {
		private {
			// stores a list of all the children that this actor created.
			// they may be null (have been killed).
			shared(Actor)[] _children;
			shared(Actor) supervisor_;
			bool isLocalInstance_;
			bool isAlive_ = true;
			bool isDying_ = false;
			string identifier_;
		}
		
		this(shared(Actor) supervisor = null, bool isLocalInstance = true) {
			this.supervisor_ = supervisor;
			this.isLocalInstance_ = isLocalInstance;
		}
		
		final {
			/**
			 * Creates a new actor instance or finds one that is already available.
			 */
			shared(T) actorOf(T : Actor)() {
				if (__ctfe && is(typeof(this) == Actor)) {
					pragma(msg, "You sure you want to CTFE actorOf " ~ typeText!T ~ "?");
					return null;
				} else {
					foreach(child; _children) {
						if (child.classinfo == T.classinfo) {
							return cast(shared(T))child;
						}
					}
					
					auto ret = new shared ActorRef!T(cast(shared)this);
					_children ~= ret;
					return ret;
				}
			}
		}
		
		@property {
			shared(Actor)[] children() { return _children; }
			shared(Actor) supervisor() { return supervisor_; }
			bool isLocalInstance() { return isLocalInstance_; }
			bool isAlive() { return isAlive_; }
			string identifier() { return identifier_; }
		}
		
		/**
		 * Lets go die.
		 */
		void die(bool informSupervisor = true) {
			import dakka.base.remotes.defs;
			import dakka.base.registration.actors : destoreActor;
			auto director = getDirector();

			if (informSupervisor) {
				if (supervisor !is null) {
					if (supervisor.isLocalInstance || director.validAddressIdentifier((cast(ActorRef!(Actor))supervisor).remoteAddressIdentifier)) {
						(cast(shared Actor)supervisor).kill(cast(shared)this);
					}
				}
			}

			// stop any more errors being received.
			isDying_ = true;
			
			// inform the central code that we are removing one.
			// it'll handle calling onStop
			(cast(Actor)this).onStop();

			// this will enable calling of methods that may be wrapped, by it being set after onstop.
			isAlive_ = false;

			foreach(child; _children) {
				child.die();
			}

			// no point in it being in destructor.
			// As it is also stored within the actor registration
			//  (so won't have that called till the reference in the actor registration goes bye bye).
			director.localActorDies(typeText!(typeof(this)), identifier);
			destoreActor(identifier_);
		}
		
		/**
		 * Kills off a specific child
		 */
		void kill(shared(Actor) actor) {
			shared(Actor[]) newChildren;
			
			foreach(child; _children) {
				if (cast(Actor)child == cast(Actor)actor) {
					child.die(false);
				} else {
					newChildren ~= child;
				}
			}
			
			_children = newChildren;
		}
	}
	
	void onStart() {}
	void onStop() {}
	void onChildError(string classIdentifier, string classInstanceIdentifier, string message) {}
}

class ActorRef(T : Actor) : T {
	import dakka.base.remotes.defs : getDirector;
	import dakka.base.registration.actors : canLocalCreate, storeActor;

	shared {
		private {
			T localRef;
			string remoteAddressIdentifier;
		}

		this(string identifier, string remoteAddress) {
			identifier_ = identifier;
			remoteAddressIdentifier = remoteAddressIdentifier;
		}
		
		this(shared(Actor) supervisor = null) {
			auto director = getDirector();
			enum type = typeText!T;

			bool createRemotely = director.canCreateRemotely!T && director.preferablyCreateRemotely!T;

			if (createRemotely) {
				// hey director, you think you could you know find a node to create it upon?
				string addr = director.preferableRemoteNodeCreation(type);
				if (addr !is null) {
					// then go send a request to create it?
					string identifier = director.createClass(addr, type, supervisor.identifier_);
					// lastly I'll store that info.
					if (identifier !is null) {
						identifier_ = identifier;
						remoteAddressIdentifier = addr;
					} else {
						// hey supervisor... we couldn't create this reference. What do you want to do now?
					}
				} else {
					// hey supervisor... we couldn't create this reference. What do you want to do now?
				}
			} else if (canLocalCreate!T) {
				// well this is easy.
				// register it with out director as our current instance.
				localRef = new shared T(supervisor);
				identifier_ = director.localActorCreate(typeText!T);
				storeActor(localRef);
				(cast(T)localRef).onStart();
			}
		}
		
		pragma(msg, getActorImplComs!T);
		mixin(getActorImplComs!T);
	}
}

pure string typeText(T)() {
	static if (__traits(compiles, {string mName = moduleName!T;})) {
		return moduleName!T ~ "." ~ T.stringof;
	} else {
		return T.stringof;
	}
}

enum DakkaNodeType {
	Local,
	Remote
}

struct DakkaCapability {
	string name;
}