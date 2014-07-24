module dakka.vibe.server;
import dakka.base.defs;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse, SessionOption;
import vibe.http.common : HTTPVersion, HTTPMethod, CookieValueMap;
import vibe.http.session : Session;
import vibe.http.status : HTTPStatus;
import vibe.inet.webform : FormFields;
import vibe.inet.message : InetHeaderMap;
import vibe.data.json : Json;
import std.datetime : SysTime;

final struct RequestData {
	//HTTPRequest
	HTTPVersion httpVersion;
	HTTPMethod method;
	string requestURL;

	//HTTPServerRequest
	string peer;
	bool ssl;
	string path;
	string username;
	string password;
	string queryString;
	CookieValueMap cookies;
	string[string] params;

	// not included by arg copy

	//HTTPRequest
	string[string] headers;

	//HTTPServerRequest
	string[string] query;
	string[string] form;

	ushort port;
	SysTime timeCreated;
}

class HTTPReqResp : Actor {
	import cerealed.attrs;

	@NoCereal private __gshared {
		HTTPServerRequest request_;
		HTTPServerResponse response_;
		Session session_;
		bool reassigned;
	}

	@DakkaLocalOnly
	void assignData(HTTPServerRequest request, HTTPServerResponse response) {
		synchronized {
			reassigned = true;
			request_ = request;
			response_ = response;
			session_ = request.session;
		}
	}

	@NoCereal {
		@property {
			bool hasBeenReassigned() {
				synchronized {
					if (reassigned) {
						reassigned = false;
						return true;
					} else {
						return false;
					}
				}
			}

			/*
			 * Request 
			 */

			RequestData request() {
				import vibe.utils.array : FixedAppender;

				synchronized {
					string[string] headers;
					foreach(key, value; request_.headers)
						headers[key] = value;
					string[string] query;
					foreach(key, value; request_.query)
						headers[key] = value;
					string[string] form;
					foreach(key, value; request_.form)
						headers[key] = value;
					ushort port = *cast(ushort*)(&request_)[SysTime.sizeof + FixedAppender!(string, 31).sizeof]; // workaround
					return mixin("RequestData(" ~ argsFromNames!(RequestData, "request_")(11) ~ ", headers, query, form, port, request_.timeCreated)");
				}
			}

			@DakkaLocalOnly {
				import dakka.vibe.client : DakkaHTTPRequest, DakkaHTTPResponse;
				DakkaHTTPRequest client_request() { return new DakkaHTTPRequest(this); }
				DakkaHTTPResponse client_response() { return new DakkaHTTPResponse(this); }
			}
		}

		/*
		 * Response
		 */

		void response_writeBody(ubyte[] data, string content_type = null) {
			synchronized
				response_.writeBody(data, content_type);
		}

		void response_writeVoidBody() {
			synchronized
				response_.writeVoidBody();
		}

		void response_redirect(string url, int status = HTTPStatus.Found) {
			synchronized
				response_.redirect(url, status);
		}

		void response_setCookie(string name, string value, string path = "/", long maxAge = long.min, string expires = null, string domain=null) {
			synchronized {
				auto cookie = response_.setCookie(name, value, path);
				if (maxAge != long.min)
					cookie.maxAge = maxAge;
				if (expires !is null)
					cookie.expires = expires;
				if (domain !is null)
					cookie.domain = domain;
			}

		}

		void response_startSession(string path = "/", size_t options = SessionOption.httpOnly) {
			synchronized
				session_ = response_.startSession(path, cast(SessionOption)options);
		}

		void response_terminateSession() {
			synchronized
				response_.terminateSession();
		}

		/*
		 * Session
		 */

		bool session_isnull() {
			synchronized
				return session_.id is null;
		}

		string session_id() {
			synchronized {
				assert(session_.id !is null, "Session is currently null. Cannot get id from it.");
				return session_.id;
			}
		}

		bool session_isKeySet(string name) {
			synchronized {
				assert(session_.id !is null, "Session is currently null. Cannot get id from it.");
				return session_.isKeySet(name);
			}
		}

		void session_set(string key, string value) {
			synchronized {
				assert(session_.id !is null, "Session is currently null. Cannot get id from it.");
				session_.set(key, value);
			}
		}

		string session_get(string key) {
			synchronized	{
				assert(session_.id !is null, "Session is currently null. Cannot get id from it.");
				return session_.get!string(key);
			}
		}

		string[] session_keys() {
			synchronized {
				assert(session_.id !is null, "Session is currently null. Cannot get id from it.");
				string[] ret;
				foreach(k, v; session_) {
					ret ~= k;
				}
				return ret;
			}
		}
	}
}

private {
	pure string argsFromNames(T, string name)(size_t max = size_t.max) {
		enum T t = T.init;
		string ret;
		foreach(i, id; __traits(allMembers, T)) {
			if (id != "opAssign" && i < max)
				ret ~= name ~ "." ~ id ~ ",";
		}
		ret.length--;
		return ret;
	}
}