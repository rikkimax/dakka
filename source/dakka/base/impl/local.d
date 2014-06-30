module dakka.base.impl.local;
import dakka.base.impl.defs;
import dakka.base.defs;

pure string generateFuncLocalHandler(T : Actor, string m)() {
	string ret;
	ret ~= "            synchronized(localRef) {\n";

	ret ~= "                if(supervisor !is null && !isAlive_) {\n";
	ret ~= "                    if ((supervisor.isLocalInstance && supervisor.isAlive_ && !supervisor.isDying_) || (!supervisor.isLocalInstance && getDirector().validAddressIdentifier((cast(ActorRef!(Actor))supervisor).remoteAddressIdentifier))) {\n";
	ret ~= "                        (cast()supervisor).onChildError(this, \"Node instance is on a remote server. But it has been disconnected.\");\n";
	ret ~= "                    } else {\n";
	ret ~= "                        die();\n";
	ret ~= "                    }\n";
	ret ~= "                }\n";

	static if (hasReturnValue!(T, m)) {
		// this shouldn't be pushed into a new thread. Blocks because we have a return type.
		ret ~= "                return localRef." ~ m ~ "(" ~ generateFuncCall!(T, m) ~ ");\n";
	} else {
		// with a void return type, we want to push this into another thread. Asynchronous because we don't have a return type. No point blocking is there?
		ret ~= "                runTask({\n";
		ret ~= "                    localRef." ~ m ~ "(" ~ generateFuncCall!(T, m) ~ ");\n";
		ret ~= "                });\n";
	}
	
	ret ~= "            }\n";
	return ret;
}