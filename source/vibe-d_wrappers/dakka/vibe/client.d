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
module dakka.vibe.client;
import dakka.vibe.server;
import vibe.http.common : HTTPResponse, HTTPRequest, HTTPVersion, HTTPMethod;
import vibe.http.server : HTTPServerRequest, SessionOption;

class DakkaHTTPResponse : HTTPResponse {
	private {
		HTTPReqResp reqresp_;
	}

	this(HTTPReqResp reqresp) {
		reqresp_ = reqresp;
	}

	void writeBody(ubyte[] data, string content_type = null) { reqresp_.response_writeBody(data, content_type); }
	void writeVoidBody() { reqresp_.response_writeVoidBody(); }
	void redirect(string url, int status = HTTPStatus.Found) { reqresp_.response_redirect(url, status); }
	DakkaCookie setCookie(string name, string value, string path = "/") { return DakkaCookie(reqresp_, name, value, path); }
	DakkaSession startSession(string path = "/", SessionOption options = SessionOption.httpOnly) { return DakkaSession(reqresp_, path, cast(size_t)options); }
	void terminateSession() { reqresp_.response_terminateSession(); }
}

struct DakkaCookie {
	private {
		HTTPReqResp reqresp_;
		string m_name;

		string m_value;
		string m_domain;
		string m_path;
		string m_expires;
		long m_maxAge;
	}

	this(HTTPReqResp reqresp, string m_name, string value, string path) {
		reqresp_ = reqresp;
		this.m_name = m_name;
		this.m_value = value;
		this.m_path = path;
		set();
	}

	@property string name() const { return m_name; }

	@property void value(string value) { m_value = value; set(); }
	@property string value() const { return m_value; }
	
	@property void domain(string value) { m_domain = value; set(); }
	@property string domain() const { return m_domain; }
	
	@property void path(string value) { m_path = value; set(); }
	@property string path() const { return m_path; }
	
	@property void expires(string value) { m_expires = value; set(); }
	@property string expires() const { return m_expires; }
	
	@property void maxAge(long value) { m_maxAge = value; set(); }
	@property long maxAge() const { return m_maxAge; }

	void set() { reqresp_.response_setCookie(m_name, m_value, m_path, m_maxAge, m_expires, m_domain); }
}

final struct DakkaSession {
	private {
		string id_;
		HTTPReqResp reqresp_;
	}

	this(HTTPReqResp reqresp, string path, size_t options) {
		reqresp_ = reqresp;
		reqresp.response_startSession(path, options);
		id_ =  reqresp.session_id;
	}

	bool opCast() { return !reqresp_.session_isnull; }
	@property string id() const { return id_; }
	bool isKeySet(string key) { return reqresp_.session_isKeySet(key); }

	T get(T)(string key, lazy T def_value = T.init) {
		import std.conv : to;

		if (isKeySet(key))
			static if (is(T == string))
				return reqresp_.session_get(key);
			else
				return to!T(reqresp_.session_get(key));
		else
			return def_value;
	}

	void set(T)(string key, T value) {
		import std.conv : to;
		static if (is(T == string))
			reqresp_.session_set(key, value);
		else
			reqresp_.session_set(key, to!string(value));
	}

	int opApply(int delegate(string key, string value) del) {
		foreach(key; reqresp_.session_keys)
			if( auto ret = del(key, reqresp_.session_get(key)) != 0 )
				return ret;
		return 0;
	}

	string opIndex(string name) { return reqresp_.session_get(name); }
	void opIndexAssign(string value, string name) { set(name, value); }
}

class DakkaHTTPRequest : HTTPRequest {
	HTTPServerRequest requestImpl;
	alias requestImpl this;

	this(HTTPReqResp reqresp) {
		auto data = reqresp.request;
        import std.datetime : SysTime;
        requestImpl = new HTTPServerRequest(SysTime.fromISOExtString(data.timeCreated), data.port);

		mixin(settingFromType!(RequestData, "data")(11));
		foreach(k, v; data.headers) {
			headers[k] = v;
			requestImpl.headers[k] = v;
		}
		foreach(k, v; data.query) {
			requestImpl.query[k] = v;
		}
		foreach(k, v; data.form) {
			requestImpl.form[k] = v;
		}
	}
}

private {
	pure string settingFromType(T, string name)(size_t max = size_t.max) {
		enum T t = T.init;
		string ret;
		foreach(i, id; __traits(allMembers, T)) {
			if (id != "opAssign" && i < max)
				ret ~= "static if (__traits(hasMember, typeof(this), \""~ id ~ "\"))" ~ id ~ " = " ~ name ~ "." ~ id ~ ";";
		}
		return ret;
	}
}