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
	ubyte[]delegate(string, ubyte[], string=null)[string] localCallInstance;
}

void registerActor(T : Actor)() {
	synchronized {
		enum type = typeText!T;

		capabilityClasses[type] = [];
		foreach(UDA; __traits(getAttributes, T)) {
			static if (__traits(compiles, {DakkaCapability c = UDA;})) {
				capabilityClasses[type] ~= UDA.name;
			}
		}
		classesInfo[type] = extractActorInfo!T;

		createLocalReferenceInstance[type] = {
			static if (isASingleton!T) {
				if (type !in localInstances)
					localInstances[type] = cast(shared)new ActorRef!T;
				return cast(shared)localInstances[type];
			} else
				return cast(shared)new ActorRef!T;
		};

		createLocalReferenceInstanceNonRef[type] = {
			static if (isASingleton!T) {
				if (type !in localInstances)
					localInstances[type] = cast(shared)new T;
				return cast(shared(T))localInstances[type];
			} else
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

void storeActor(T : Actor)(T actor) {
	synchronized {
		localInstances[actor.identifier] = cast(shared)actor;
		localCallInstance[actor.identifier] = (string method, ubyte[] args, string addr=null) {return handleCallActorMethods!T(actor, method, args, addr);};
	}
}

void destoreActor(string identifier) {
	synchronized {
		localInstances.remove(identifier);
		localCallInstance.remove(identifier);
	}
}

Actor getInstance(string identifier) {
	synchronized {
		return cast()localInstances[identifier];
	}
}

bool hasInstance(string identifier) {
	synchronized {
		return identifier in localInstances ? true : false;
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

ubyte[] callMethodOnActor(string identifier, string method, ubyte[] data, string addr=null) {
	synchronized {
		assert(identifier in localCallInstance, "Class " ~ identifier ~ " has not been created.");
		return localCallInstance[identifier](method, data, addr);
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

	string getValuesFromDeserializer(T : Actor, string m)(T t = T.init) {
		string ret;

		//Decerealizer
		foreach(i, n; ParameterTypeTuple!(mixin("t." ~ m))) {
			static if (is(n == class) && is(n : Actor)) {
				ret ~= "grabActorFromData!(" ~ n.stringof ~ ")(d, addr), ";
			} else {
				ret ~= "d.value!(" ~ n.stringof ~ "), ";
			}
		}

		if (ret.length > 0)
			ret.length -= 2;

		return ret;
	}

	string grabImportsForDeserializer(T : Actor, string m)(T t = T.init) {
		string ret;
		foreach(n; ParameterTypeTuple!(mixin("t." ~ m))) {
			static if (is(n == class) || is(n == struct) || is(n == union)) {
				ret ~= "import " ~ moduleName!n ~ " : " ~ n.stringof ~ ";";
			}
		}
		return ret;
	}
}

private {
	ubyte[] handleCallActorMethods(T : Actor)(T t, string method, ubyte[] data, string addr=null) {
		foreach(m; __traits(allMembers, T)) {
			static if (__traits(getProtection, __traits(getMember, t, m)) == "public" && !hasMember!(Actor, m)) {
				static if (__traits(isVirtualFunction, __traits(getMember, t, m))) {
					if (m == method) {
						return handleCallActorMethod!(T, m)(t, data, addr);
					}
				}
			}
		}
		
		return null;
	}

	ubyte[] handleCallActorMethod(T : Actor, string m)(T t, ubyte[] data, string addr=null) {
		import cerealed;
		import dakka.base.impl.defs;
		import dakka.base.remotes.defs : grabActorFromData;
		import std.traits : moduleName;
		
		auto d = Decerealizer(data);
		mixin(grabImportsForDeserializer!(T, m));

		static if (!hasReturnValue!(T, m)) {
			// call
			mixin("t." ~ m ~ "(" ~ getValuesFromDeserializer!(T, m) ~ ");");
			return null;
		} else {
			// store ret during call
			mixin("auto ret = t." ~ m ~ "(" ~ getValuesFromDeserializer!(T, m) ~ ");");
			
			// serialize ret
			auto c = Cerealiser();
			static if (is(typeof(ret) == class) && is(typeof(ret) : Actor)) {
				c.write(DakkaActorRefWrapper(ret.identifier, ret.isLocalInstance ? null : (ret.remoteAddressIdentifier == remoteAddressIdentifier ? null : ret.remoteAddressIdentifier)));
			} else {
				c ~= ret;
			}
			
			// return ret
			return cast(ubyte[])c.bytes;
		}
	}
}