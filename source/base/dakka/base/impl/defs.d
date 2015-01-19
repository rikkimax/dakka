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
module dakka.base.impl.defs;
import dakka.base.defs;
import std.traits;

pure string getActorImplComs(T : Actor, T t = T.init)() {
	string ret;
	ret ~= "override {\n";
	
	foreach(m; __traits(allMembers, T)) {
		static if (__traits(compiles, __traits(getMember, t, m)) && __traits(getProtection, __traits(getMember, t, m)) == "public" && !hasMember!(Actor, m)) {
			static if (__traits(isVirtualFunction, __traits(getMember, t, m))) {
				static if (!isMethodLocalOnly!(T, m)) {
					ret ~= funcDeclText!(T, m);
					ret ~= generateFuncHandler!(T, m);
					ret ~= "    }\n";
                }
			}
		}
	}
	
	ret ~= "}\n";
	return ret;
}

pure string funcDeclText(T : Actor, string m, T t = T.init)(bool multiRet = false) {
	string ret;
	string ret2;

	ret ~= typeText!(ReturnType!(__traits(getMember, t, m)));
	if (multiRet)
		ret ~= "[]";

	ret ~= " " ~ m ~ "(";
	
	enum names = ParameterIdentifierTuple!(mixin("t." ~ m));
	foreach(i, a; ParameterTypeTuple!(mixin("t." ~ m))) {
		static if (is(a == class) || is(a == struct) || is(a == union)) {
			ret2 ~= "    import " ~ moduleName!a ~ " : " ~ a.stringof ~ ";\n";
		}
		ret ~= a.stringof ~ " " ~ names[i] ~ ", ";
	}
	
	if (ret[$-2] == ',')
		ret.length -= 2;
	
	ret ~= ") {\n";
	return ret2 ~ "    " ~ ret;
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

pure string generateFuncCall(T : Actor, string m, T t = T.init)() {
	string ret;
	foreach(n; ParameterIdentifierTuple!(mixin("t." ~ m))) {
		ret ~= n ~ ", ";
	}
	
	if (ret.length > 0)
		if (ret[$-2] == ',')
			ret.length -= 2;
	return ret;
}

pure bool hasReturnValue(T : Actor, string m, T t = T.init)() {
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