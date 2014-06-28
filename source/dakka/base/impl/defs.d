module dakka.base.impl.defs;
import dakka.base.defs;
import std.traits;

pure string getActorImplComs(T : Actor, T t = new T())() {
	string ret;
	ret ~= "override {\n";
	
	foreach(m; __traits(allMembers, T)) {
		static if (__traits(getProtection, __traits(getMember, t, m)) == "public" && !hasMember!(Actor, m)) {
			static if (__traits(isVirtualFunction, __traits(getMember, t, m))) {
				ret ~= "    " ~ funcDeclText!(T, m);
				ret ~= generateFuncHandler!(T, m);
				ret ~= "    }\n";
			}
		}
	}
	
	ret ~= "}\n";
	return ret;
}

pure string funcDeclText(T : Actor, string m, T t = new T())() {
	string ret;
	ret ~= typeText!(ReturnType!(__traits(getMember, t, m)));
	ret ~= " " ~ m ~ "(";
	
	enum names = ParameterIdentifierTuple!(mixin("t." ~ m));
	foreach(i, a; ParameterTypeTuple!(mixin("t." ~ m))) {
		ret ~= typeText!(a) ~ " " ~ names[i] ~ ", ";
	}
	
	if (ret[$-2] == ',')
		ret.length -= 2;
	
	ret ~= ") {\n";
	return ret;
}

pure string generateFuncHandler(T : Actor, string m)() {
	import dakka.base.impl.local;
	import dakka.base.impl.remote;

	string ret;
	ret ~= "        if (isLocalInstance) {\n";
	ret ~= generateFuncLocalHandler!(T, m);
	ret ~= "        } else {\n";
	
	ret ~= generateFuncRemoteHandler!(T, m);
	// theres a few things that need to go on here
	// grab arguments of function, serialize them
	// send them with our id's to server
	// wait and receive the result
	// if is an exception, recreate it and throw it
	// otherwise deserialize our value and return it
	
	//ret ~= "            assert(0);\n";
	ret ~= "        }\n";
	
	return ret;
}

pure string packFormat(T : Actor, string m, T t = new T())() {
	import binary.format;
	import std.conv : to;

	static if (ParameterTypeTuple!(__traits(getMember, t, m)).length == 1) {
		enum char format = formatCharOf!(ParameterTypeTuple!(__traits(getMember, t, m))[0]);
		pragma(msg, format);
		return to!string(format);
	} else static if (ParameterTypeTuple!(__traits(getMember, t, m)).length > 1) {
		return formatOf!(ParameterTypeTuple!(__traits(getMember, t, m)));
	} else {
		return "";
	}
}

pure string generateFuncCall(T : Actor, string m, T t = new T())() {
	string ret;
	foreach(n; ParameterIdentifierTuple!(mixin("t." ~ m))) {
		ret ~= n ~ ", ";
	}
	
	if (ret.length > 0)
		if (ret[$-2] == ',')
			ret.length -= 2;
	return ret;
}

pure bool hasReturnValue(T : Actor, string m, T t = new T())() {
	static if (ReturnType!(__traits(getMember, t, m)).stringof != "void") {
		return true;
	} else {
		foreach(p; ParameterStorageClassTuple!(mixin("t." ~ m))) {
			static if (p == ParameterStorageClass.ref_ || p == ParameterStorageClass.out_) {
				return true;	
			}
		}
		
		return false;
	}
}