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
module dakka.base.impl.local;
import dakka.base.impl.defs;
import dakka.base.defs;

pure string generateFuncLocalHandler(T : Actor, string m)() {
	import std.traits : ReturnType;
	enum T t = T.init;

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
		ret ~= "                try {\n";
		ret ~= "                    return localRef." ~ m ~ "(" ~ generateFuncCall!(T, m) ~ ");\n";
		ret ~= "                } catch(Exception e) {\n";
		ret ~= "                    if(supervisor !is null) {\n";
		ret ~= "                        if (supervisor.isLocalInstance || (!supervisor.isLocalInstance && getDirector().validAddressIdentifier((cast(ActorRef!(Actor))supervisor).remoteAddressIdentifier))) {\n";
		ret ~= "                            (cast()supervisor).onChildError(this, e.toString());\n";
		ret ~= "                        } else {\n";
		ret ~= "                            die();\n";
		ret ~= "                        }\n";
		ret ~= "                    }\n";
		ret ~= "                    return " ~ typeText!(ReturnType!(mixin("t." ~ m))) ~ ".init;\n";
		ret ~= "                }\n";
	} else {
		// with a void return type, we want to push this into another thread. Asynchronous because we don't have a return type. No point blocking is there?
		ret ~= "                runTask({\n";
		ret ~= "                    try {\n";
		ret ~= "                        localRef." ~ m ~ "(" ~ generateFuncCall!(T, m) ~ ");\n";
		ret ~= "                    } catch(Exception e) {\n";
		ret ~= "                        if(supervisor !is null) {\n";
		ret ~= "                            if (supervisor.isLocalInstance || (!supervisor.isLocalInstance && getDirector().validAddressIdentifier((cast(ActorRef!(Actor))supervisor).remoteAddressIdentifier))) {\n";
		ret ~= "                                (cast()supervisor).onChildError(this, e.toString());\n";
		ret ~= "                            } else {\n";
		ret ~= "                                die();\n";
		ret ~= "                            }\n";
		ret ~= "                        }\n";
		ret ~= "                    }\n";
		ret ~= "                });\n";
	}
	
	ret ~= "            }\n";
	return ret;
}