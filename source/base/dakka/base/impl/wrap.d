module dakka.base.impl.wrap;
import dakka.base.impl.defs;
import dakka.base.defs;
import std.traits : hasMember, ReturnType, ParameterIdentifierTuple;

pure string getActorWrapImpl(T : Actor)(T t = T.init) {
	string ret;

	foreach(m; __traits(allMembers, T)) {
		static if (__traits(getProtection, __traits(getMember, t, m)) == "public" && !hasMember!(Actor, m)) {
			static if (__traits(isVirtualFunction, __traits(getMember, t, m))) {
				static if (!isMethodLocalOnly!(T, m)) {
                    ret ~= funcDeclText!(T, m)(!is(ReturnType!(mixin("t." ~ m)) == void));

					switch(getCallUDA!(T, m).strategy) {
						case DakkaCallStrategy.Until:
							untilWrapStrategy!(T, m)(ret);
							break;

						case DakkaCallStrategy.Sequentially:
						default:
							sequentialWrapStrategy!(T, m)(ret);
							break;
					}

					ret ~= "    }\n";
				}
			}
		}
	}

	return ret;
}

pure DakkaCall_ getCallUDA(T : Actor, string m)() {
	enum T t = T.init;
	foreach(UDA; __traits(getAttributes, mixin("t." ~ m))) {
		if (typeText!(typeof(UDA)) == typeText!DakkaCall_) {
			return UDA;
		}
	}

	return DakkaCall(DakkaCallStrategy.Sequentially);
}

pure void sequentialWrapStrategy(T, string m)(ref string ret) {
	enum uda = getCallUDA!(T, m);
	enum T t = T.init;

	string names;
	foreach(name; ParameterIdentifierTuple!(mixin("t." ~ m))) {
		names ~= name ~ ", ";
	}
	if (names.length > 0)
		names.length -= 2;

    if (is(ReturnType!(mixin("t." ~ m)) == void)) {
    	ret ~= ("""
     	checkForUpdatesToAddresses();

    	localRef." ~ m ~ "(" ~ names ~ ");
    	foreach(actor; remoteRefs.values) {
    		actor." ~ m ~ "(" ~ names ~ ");
    	}
""")[1 .. $];
    } else {
        ret ~= ("""
        checkForUpdatesToAddresses();
        " ~ typeText!(ReturnType!(mixin("t." ~ m))) ~ "[] ret;

        ret ~= localRef." ~ m ~ "(" ~ names ~ ");
        foreach(actor; remoteRefs.values) {
            ret ~= actor." ~ m ~ "(" ~ names ~ ");
        }
        return ret;
""")[1 .. $];
    }
}

pure void untilWrapStrategy(T, string m)(ref string ret) {
	enum uda = getCallUDA!(T, m);
	enum T t = T.init;
	import std.conv : to;
	
	string names;
	foreach(name; ParameterIdentifierTuple!(mixin("t." ~ m))) {
		names ~= name ~ ", ";
	}
	if (names.length > 0)
		names.length -= 2;
	
	ret ~= ("""
	checkForUpdatesToAddresses();
	" ~ typeText!(ReturnType!(mixin("t." ~ m))) ~ "[] ret;

	" ~ typeText!(ReturnType!(mixin("t." ~ m))) ~ " vcmp = Decerealizer(" ~ to!string(uda.data) ~ ").value!(" ~ typeText!(ReturnType!(mixin("t." ~ m))) ~ ");

	ret ~= localRef." ~ m ~ "(" ~ names ~ ");
	if (ret[0] == vcmp)
 	 	return ret;

	foreach(actor; remoteRefs.values) {
		" ~ typeText!(ReturnType!(mixin("t." ~ m))) ~ " v = actor." ~ m ~ "(" ~ names ~ ");
		ret ~= v;
		if (v == vcmp)
			break;
	}
 	return ret;
""")[1 .. $];
}