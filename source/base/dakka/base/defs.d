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
module dakka.base.defs;
import dakka.base.impl.defs;

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
	import cerealed;

	this(Actor supervisor = null, bool isLocalInstance = true) {
		this.supervisor_ = supervisor;
		this.isLocalInstance_ = isLocalInstance;
	}

	private {
		// stores a list of all the children that this actor created.
		// they may be null (have been killed).
		Actor[] _children;
		Actor supervisor_;
		bool isAlive_ = true;
		bool isDying_ = false;

		string identifier_;
		string remoteAddressIdentifier_;
		bool isLocalInstance_;
	}
	
	final {
		/**
		 * Creates a new actor instance or finds one that is already available.
		 */
		T actorOf(T : Actor)() {
			if (__ctfe && is(typeof(this) == Actor)) {
				pragma(msg, "You sure you want to CTFE actorOf " ~ typeText!T ~ "?");
				return null;
			} else {
				foreach(child; _children) {
					if (child.classinfo == T.classinfo) {
						return cast(T)child;
					}
				}

				auto ret = new ActorRef!T(this);
				_children ~= ret;
				return ret;
			}
		}

		Actor referenceOfActor() {
			return new ActorRef!(typeof(this));
		}
	}
	
	@property {
		Actor[] children() { return _children; }
		Actor supervisor() { return supervisor_; }
		bool isLocalInstance() { return isLocalInstance_; }
		bool isAlive() { return isAlive_; }
		string identifier() { return identifier_; }
		string remoteAddressIdentifier() { return remoteAddressIdentifier_; }
	}
	
	/**
	 * Lets go die.
	 */
	void die(bool informSupervisor = true) {
		import dakka.base.remotes.defs;
		import dakka.base.registration.actors : destoreActor;

		// seems silly to do anything if its a remote instance.
		// we don't know what to do with it.
		// leave it for the ActorRef
		if (!isDying_ && isAlive_ && isLocalInstance_) {
			// stop any more errors being received.
			isDying_ = true;
			auto director = getDirector();

			if (informSupervisor) {
				if (supervisor !is null) {
					if (supervisor.isLocalInstance || director.validAddressIdentifier((cast(ActorRef!(Actor))supervisor).remoteAddressIdentifier)) {
						supervisor.kill(this);
					}
				}
			}

			onStop();

			// this will enable calling of methods that may be wrapped, by it being set after onstop.
			isAlive_ = false;
			isDying_ = false;

			foreach(child; _children) {
				child.die();
			}
		}
	}
	
	/**
	 * Kills off a specific child
	 */
	void kill(Actor actor) {
		Actor[] newChildren;
		
		foreach(child; _children) {
			if (cast(Actor)child == cast(Actor)actor) {
				child.die(false);
			} else {
				newChildren ~= child;
			}
		}
		
		_children = newChildren;
	}

	void onStart() {}
	void onStop() {}
	void onChildError(Actor actor, string message) {}
}

class ActorRef(T : Actor) : T {
	import dakka.base.remotes.defs : getDirector, DakkaActorRefWrapper;
	import dakka.base.registration.actors : canLocalCreate, storeActor, createLocalActorNonRef;

	this(string identifier, string remoteAddress) {
		identifier_ = identifier;
		remoteAddressIdentifier_ = remoteAddress;
		isLocalInstance_ = false;
	}
	
	this(Actor supervisor = null, bool isActualInstance = false) {
		import vibe.d : runTask;
		auto director = getDirector();
		enum type = typeText!T;

		if (isActualInstance) {
			localRef = cast(T)supervisor;
			identifier_ = supervisor.identifier_;
		} else {
			bool createRemotely = director.canCreateRemotely!T && director.preferablyCreateRemotely!T;

			if (createRemotely) {
				// hey director, you think you could you know find a node to create it upon?
				string addr = director.preferableRemoteNodeCreation(type);
				if (addr !is null) {
					// then go send a request to create it?
					string identifier = director.createClass(addr, type, supervisor is null ? null : supervisor.identifier_);
					// lastly I'll store that info.
					if (identifier !is null) {
						identifier_ = identifier;
						remoteAddressIdentifier_ = addr;
						isLocalInstance_ = false;
					} else {
						// hey supervisor... we couldn't create this reference. What do you want to do now?
						assert(0, "no identifier");
					}
				} else {
					// hey supervisor... we couldn't create this reference. What do you want to do now?
					assert(0, "no address");
				}
			} else {
				// well this is easy.
				// register it with out director as our current instance.
				// also don't forget that could be a singleton. have it handled centurally.
				localRef = cast(T)createLocalActorNonRef(type);
				if (localRef.identifier_ is null) {
					identifier_ = director.localActorCreate(typeText!T);
					localRef.identifier_ = identifier_;
					storeActor!T(localRef);

					// new thread for on start. Yes its evil. But it'll work.
					runTask({ (cast(T)localRef).onStart(); });
				}
			}
		}
	}

	private {
		T localRef;
	}

	override {
		void die(bool informSupervisor = true) {
			import dakka.base.registration.actors : destoreActor;
			
			auto director = getDirector();
			enum type = typeText!T;
			
			if (isLocalInstance_ && !isDying_ && isAlive_) {
				super.die(informSupervisor);
				
				// no point in it being in destructor.
				// As it is also stored within the actor registration
				//  (so won't have that called till the reference in the actor registration goes bye bye).
				director.localActorDies(type, identifier);
				destoreActor(identifier_);
			} else {
				director.killClass(remoteAddressIdentifier, type, identifier);
			}
		}

		void onChildError(Actor actor, string message) {
			if (isLocalInstance_) {
				super.onChildError(actor, message);
			} else {
				// assuming the remote node will know about this actor. After all, it contains the supervisor for it!
				getDirector().actorError(remoteAddressIdentifier, identifier_, (actor !is null ? actor.identifier_ : ""), message);
			}
		}
	}

	mixin(getActorImplComs!T);
}

class AllActorRefs(T : Actor) if (isASingleton!T) {
	import dakka.base.impl.wrap;
	import dakka.base.registration.actors : createLocalActorNonRef;
	import dakka.base.remotes.defs : getDirector;
	import cerealed.decerealizer;

	private {
		T localRef;
		ActorRef!T[string] remoteRefs; // actor[remoteAddressIdentifier]
	}

	this() {
		localRef = cast(T)createLocalActorNonRef(typeText!T); // because singleton and local
	}

	// implement the methods overloading

	void checkForUpdatesToAddresses() {
		import std.algorithm : equal;

		auto director = getDirector();

		//   grab all of the current ones
		string[] allRemoteAddresses = director.allRemoteAddresses();

		// does remoteRefs.keys != addrs
		if (!equal(remoteRefs.keys, allRemoteAddresses)) {

			//   remoteRefs = []
			remoteRefs = remoteRefs.init;

			//   foreach addr in addrs
			foreach(addr; allRemoteAddresses) {
				//       remoteRefs[addr] = director.createClass(addr, typeText!T);
				remoteRefs[addr] = new ActorRef!T(director.createClass(addr, typeText!T, null), addr);
			}
		}
	}
	 
	mixin(getActorWrapImpl!T);
}

pure string typeText(T)() {
	import std.traits : moduleName;
	static if (is(T == class) || is(T == struct) || is(T == union)) {
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

struct DakkaSingleton {}

pure bool isASingleton(T : Actor)() {
	foreach(uda; __traits(getAttributes, T)) {
		static if (is(uda == DakkaSingleton)) {
			return true;
		}
	}

	return false;
}

struct DakkaLocalOnly {}
pure bool isMethodLocalOnly(T : Actor, string m)() {
	enum T t = T.init;
	foreach(uda; __traits(getAttributes, mixin("t." ~ m))) {
		static if (is(uda == DakkaLocalOnly)) {
			return true;
		}
	}
	
	return false;
}

enum DakkaCallStrategy {
	Sequentially,
	Until
}

struct DakkaCall_ {
	DakkaCallStrategy strategy;
	ubyte[] data;
}

pure DakkaCall_ DakkaCall(DakkaCallStrategy strategy) {
	return DakkaCall_(strategy);
}

pure DakkaCall_ DakkaCall(T)(DakkaCallStrategy strategy, T t) {
	import cerealed.cerealizer;
	Cerealizer c;
	c ~= t;

	return DakkaCall_(strategy, cast(ubyte[])c.bytes);
}