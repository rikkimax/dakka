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
module dakka.base.impl.remote;
import dakka.base.impl.defs;
import dakka.base.defs;
import std.traits : ParameterIdentifierTuple, ParameterTypeTuple, ReturnType, isArray, isSomeString;

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
			ret ~= "            cereal.write(DakkaActorRefWrapper(" ~ n ~ ".identifier, " ~ n ~ ".isLocalInstance_ ? null : (" ~ n ~ ".remoteAddressIdentifier == remoteAddressIdentifier ? null : " ~ n ~ ".remoteAddressIdentifier)));\n";
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
			ret ~= "            return grabActorFromData!(" ~ typeText!(ReturnType!(__traits(getMember, t, m))) ~ ")(decereal);";
		} else {
            if (isArray!(ReturnType!(__traits(getMember, t, m))) && !isSomeString!(ReturnType!(__traits(getMember, t, m)))) {
                ret ~= "            import dakka.base.remotes.messages;\n";
                ret ~= "            RawConvTypes!(string[]) ret;\n";
                ret ~= "            ret.bytes = odata;\n";
                ret ~= "            return ret.value;\n";
            } else
			    ret ~= "            return decereal.value!(" ~ typeText!(ReturnType!(__traits(getMember, t, m))) ~ ");\n";
		}
	} else {
		// non blocking request
		ret ~= "            getDirector().callClassNonBlocking(remoteAddressIdentifier, identifier, \"" ~ m ~ "\", cast(ubyte[])cereal.bytes);\n";
	}
	return ret;
}