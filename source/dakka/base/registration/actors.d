module dakka.base.registration.actors;
import dakka.base.registration.capabilities;
import dakka.base.remotes.messages : ActorInformation;
import dakka.base.defs;

__gshared private {
	string[][string] capabilityClasses;
	ActorInformation[string] classesInfo;

	shared(Actor)[string] localInstances; // instance[instanceIdentifier]
	string[][string] remoteInstances; // instanceIdentifier[][adder]
	shared(Actor)delegate() [string] createLocalReferenceInstance;
	shared(Actor)delegate() [string] createLocalReferenceInstanceNonRef;
	shared(Actor)[string] singletonInstances; //instance[type]
}

void registerActor(T : Actor)() {
	synchronized {
		enum type = typeText!T;

		foreach(UDA; __traits(getAttributes, T)) {
			static if (__traits(compiles, {DakkaCapability c = UDA;})) {
				capabilityClasses[type] ~= UDA.name;
			}
		}
		classesInfo[type] = extractActorInfo!T;

		createLocalReferenceInstance[type] = {
			static if (isASingleton!T) {
				if (type !in singletonInstances)
					singletonInstances[type] = new T;
				return cast(shared)new ActorRef!T(cast()singletonInstances[type], true);
			}
			return cast(shared)new ActorRef!T;
		};

		createLocalReferenceInstanceNonRef[type] = {
			static if (isASingleton!T) {
				if (type !in singletonInstances)
					singletonInstances[type] = new T;
				return cast(shared(T))singletonInstances[type];
			}
			return cast(shared)new T;
		};
	}
}

bool canLocalCreate(T : Actor)() {
	return canLocalCreate(typeText!T);
}

bool canLocalCreate(string type) {
	synchronized {
		if (!hasCapabilities()) return true;
		if (type !in capabilityClasses) return true;

		foreach(c; capabilityClasses[type]) {
			if (!hasCapability(c)) return false;
		}
		
		return true;
	}
}

ActorInformation[] possibleActors() {
	synchronized {
		if (!hasCapabilities()) return classesInfo.values;

		ActorInformation[] ret;

	L1: foreach(k, v; classesInfo) {
			foreach(c; capabilityClasses[k])
				if (!hasCapability(c)) continue L1;
			ret ~= v;
		}
		
		return ret;
	}
}

string[] possibleActorNames() {
	synchronized {
		if (!hasCapabilities()) return classesInfo.keys;

		string[] ret;
		
	F1: foreach(k, v; classesInfo) {
			if (k in capabilityClasses)
				foreach(c; capabilityClasses[k])
					if (!hasCapability(c)) continue F1;
			ret ~= k;
		}

		return ret;
	}
}

ActorInformation getActorInformation(string name) {
	synchronized {
		assert(name in classesInfo, "Class " ~ name ~ " has not been registered.");
		return classesInfo[name];
	}
}

string[] capabilitiesRequired(T : Actor)() {
	synchronized {
		if (typeText!T !in capabilityClasses) return [];
		return capabilityClasses[typeText!T];
	}
}

string[] capabilitiesRequired(string identifier) {
	synchronized {
		return capabilityClasses[identifier];
	}
}

void storeActor(Actor actor) {
	synchronized {
		localInstances[actor.identifier] = cast(shared)actor;
	}
}

void destoreActor(string identifier) {
	synchronized {
		localInstances.remove(identifier);
	}
}

Actor getInstance(string identifier) {
	synchronized {
		return cast()localInstances[identifier];
	}
}

Actor createLocalActor(string type) {
	synchronized {
		assert(type in classesInfo, "Class " ~ type ~ " has not been registered.");
		return cast()createLocalReferenceInstance[type]();
	}
}

Actor createLocalActorNonRef(string type) {
	synchronized {
		assert(type in classesInfo, "Class " ~ type ~ " has not been registered.");
		return cast()createLocalReferenceInstanceNonRef[type]();
	}
}


/**
 * Dyanmic stuff for remotes
 */

private pure {
	import dakka.base.remotes.messages;
	import std.traits;

	ActorInformation extractActorInfo(T : Actor)() {
		ActorInformation ret;
		ret.name = typeText!T;
		ret.methods = extractActorMethods!T;
		return ret;
	}

	ActorMethod[] extractActorMethods(T : Actor)() {
		ActorMethod[] ret;
		T t;

		foreach(m; __traits(allMembers, T)) {
			static if (__traits(compiles, mixin("t." ~ m))) {
				static if (isCallable!(mixin("t." ~ m))) {
					ret ~= extractActorMethod!(T, m);
				}
			}
		}

		return ret;
	}

	ActorMethod extractActorMethod(T : Actor, string m)() {
		ActorMethod ret;
		ret.name = m;
		ret.return_type = typeText!(ReturnType!(__traits(getMember, T, m)));

		enum argStorage = ParameterStorageClassTuple!(__traits(getMember, T, m));
		foreach(i, arg; ParameterTypeTuple!(__traits(getMember, T, m))) {
			ActorMethodArgument argument;
			argument.type = typeText!(arg);

			if (argStorage[i] == ParameterStorageClass.out_)
				argument.usage = ActorMethodArgumentUsage.Out;
			else if (argStorage[i] == ParameterStorageClass.ref_)
				argument.usage = ActorMethodArgumentUsage.Ref;
			else
				argument.usage = ActorMethodArgumentUsage.In;

			ret.arguments ~= argument;
		}

		return ret;
	}
}