module dakka.base.impl.remote;
import dakka.base.impl.defs;
import dakka.base.defs;
import std.traits : ParameterIdentifierTuple, ParameterTypeTuple, ReturnType;

pure string generateFuncRemoteHandler(T : Actor, string m, T t = T.init)() {
	string ret;

	ret ~= "            if(supervisor !is null && !getDirector().validAddressIdentifier(remoteAddressIdentifier)) {\n";
	ret ~= "                if (supervisor.isLocalInstance || getDirector().validAddressIdentifier((cast(ActorRef!(Actor))supervisor).remoteAddressIdentifier) && !supervisor.isDying_) {\n";
	ret ~= "                    (cast()supervisor).onChildError(this, \"Node instance is on a remote server. But it has been disconnected.\");\n";
	ret ~= "                } else {\n";
	ret ~= "                    die();\n";
	ret ~= "                }\n";
	ret ~= "            }\n";

	ret ~= "            auto cereal = Cerealiser();\n";

	alias ptt = ParameterTypeTuple!(mixin("t." ~ m));
	foreach(i, n; ParameterIdentifierTuple!(mixin("t." ~ m))) {
		static if (is(ptt[i] == class) && is(ptt[i] : Actor)) {
			// TODO: complex serializer action for a possibly remote instance
		} else {
			ret ~= "            cereal.write(" ~ n ~ ");\n";
		}
	}
	
	static if (hasReturnValue!(T, m)) {
		// wait for output from central.d -> reconstruct args return
		ret ~= "            ubyte[] odata = getDirector().callClassBlocking(remoteAddressIdentifier, identifier, \"" ~ m ~ "\", cast(ubyte[])cereal.bytes);\n";
		ret ~= "            auto decereal = Decerealiser(odata);\n";
		// blocking request.

		static if (is(ReturnType!(mixin("t." ~ m)) == class) && is(ReturnType!(mixin("t." ~ m)) : Actor)) {
			// TODO: complex deserializer action for a possibly remote instance
		} else {
			ret ~= "            return cereal.value!(" ~ typeText!(ReturnType!(__traits(getMember, t, m))) ~ ");\n";
		}
	} else {
		// non blocking request
		ret ~= "            getDirector().callClassNonBlocking(remoteAddressIdentifier, identifier, \"" ~ m ~ "\", cast(ubyte[])cereal.bytes);\n";
	}

	return ret;
}