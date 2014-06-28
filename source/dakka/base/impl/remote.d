module dakka.base.impl.remote;
import dakka.base.impl.defs;
import dakka.base.defs;

pure string generateFuncRemoteHandler(T : Actor, string m, T t = new T())() {
	string ret;


	/*ret ~= "            if(supervisor !is null && !getDirector().validAddressIdentifier(remoteAddressIdentifier)) {\n";
	ret ~= "                if (supervisor.isLocalInstance || getDirector().validAddressIdentifier((cast(ActorRef!(Actor))supervisor).remoteAddressIdentifier) && !supervisor.isDying_) {\n";
	ret ~= "                    (cast()supervisor).onChildError(typeText!T, identifier, \"Node instance is on a remote server. But it has been disconnected.\");\n";
	ret ~= "                } else {\n";
	ret ~= "                    die();\n";
	ret ~= "                }\n";
	ret ~= "            }\n";*/

	enum string format = packFormat!(T, m);
	
	/*ret ~= "            ubyte[] bytes;\n";
	ret ~= "            bytes = pack!(\"" ~ format ~ "\")(" ~ generateFuncCall!(T, m) ~ ");\n";
	
	// create input func call -> central.d
	ret ~= "import std.file;append(\"out.txt\", bytes);\n";*/
	
	static if (hasReturnValue!(T, m)) {
		// wait for output from central.d -> reconstruct args return
		
		ret ~= "            return " ~ typeText!(ReturnType!(__traits(getMember, t, m))) ~ ".init;\n";
	} else {
	}

	return ret;
}