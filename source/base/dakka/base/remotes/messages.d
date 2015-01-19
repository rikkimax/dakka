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
module dakka.base.remotes.messages;
import dakka.base.remotes.defs;
import vibe.d;

struct DakkaMessage {
	ubyte stage;
	ubyte substage;
	
	union {
		string stage0_init;
		string[] stage0_capabilities;


		ulong stage1_client_sync;
		ServerLagReply stage1_server_sync;


		string[] stage2_actors;
		string stage2_actor_request;
		ActorInformation stage2_actor;


		ActorClassCreation stage3_actor_create;
		ActorClassCreationVerify stage3_actor_verify;

		string stage3_actor_destroy;
		ActorClassDestroyVerify stage3_actor_destroy_verify;

		ActorMethodCall stage3_method_call;
		ActorMethodReturn stage3_method_return;

		ActorError stage3_actor_error;
	}
	
	void receive(TCPConnection stream) {
		ubyte[2] stages;
		stream.read(stages);
		stage = stages[0];
		substage = stages[1];

		RawConvTypes!ulong size;
		stream.read(size.bytes);

		import std.conv : to;
		logInfo("size %s", to!string(size.value));

		if (stage == 0) {
			if (substage == 0) {
				stage0_init = cast(string)stream.readSome(cast(size_t)size.value);
			} else if (substage == 1 || substage == 2) {
				for(size_t count; count < size.value; count++) {
					RawConvTypes!ulong size2;
					stream.read(size2.bytes);
					stage0_capabilities ~= cast(string)stream.readSome(cast(size_t)size2.value);
				}
			}
		} else if (stage == 1) {
			if (substage == 0) {
				RawConvTypes!ulong v;
				stream.read(v.bytes);
				stage1_client_sync = v.value;
			} else if (substage == 1) {
				ubyte[2] v;
				stream.read(v);
				stage1_server_sync.isOverloaded = cast(bool)v[0];
				stage1_server_sync.willUse = cast(bool)v[1];
			}
		} else if (stage == 2) {
			if (substage == 0) {
				// do nothing. already complete
			} else if (substage == 1) {
				RawConvTypes!ulong numberOfClasses; // not needed. But lets stay standard compliant
				stream.read(numberOfClasses.bytes);

				ulong got;
				while(got < size.value) {
					RawConvTypes!ulong classLength;
					stream.read(classLength.bytes);
					stage2_actors ~= cast(string)stream.readSome(cast(size_t)classLength.value);
					got += ulong.sizeof + classLength.value;
				}
			} else if (substage == 2) {
				stage2_actor_request = cast(string)stream.readSome(cast(size_t)size.value);
			} else if (substage == 3) {
				RawConvTypes!ulong classNameLength;
				stream.read(classNameLength.bytes);
				stage2_actor.name = cast(string)stream.readSome(cast(size_t)classNameLength.value);

				RawConvTypes!ulong methodsCount;
				stream.read(methodsCount.bytes);

				for (size_t i; i < cast(size_t)methodsCount.value; i++) {
					ActorMethod method;

					RawConvTypes!ulong methodNameLength;
					stream.read(methodNameLength.bytes);
					method.name = cast(string)stream.readSome(cast(size_t)methodNameLength.value);

					RawConvTypes!ulong methodReturnTypeLength;
					stream.read(methodReturnTypeLength.bytes);
					method.return_type = cast(string)stream.readSome(cast(size_t)methodReturnTypeLength.value);

					RawConvTypes!ulong argsCount;
					stream.read(argsCount.bytes);

					for (size_t j; j < cast(size_t)argsCount.value; j++) {
						ActorMethodArgument arg;

						RawConvTypes!ulong argLength;
						stream.read(argLength.bytes);
						arg.type = cast(string)stream.readSome(cast(size_t)argLength.value);

						ubyte[1] usage;
						stream.read(usage);
						arg.usage = cast(ActorMethodArgumentUsage)usage[0];

						method.arguments ~= arg;
					}

					stage2_actor.methods ~= method;
				}
			}
		} else if (stage == 3) {
			if (substage == 0) {
				RawConvTypes!ulong uidLength;
				stream.read(uidLength.bytes);
				stage3_actor_create.uid = cast(string)stream.readSome(cast(size_t)uidLength.value);

				RawConvTypes!ulong classIdentifierLength;
				stream.read(classIdentifierLength.bytes);
				stage3_actor_create.classIdentifier = cast(string)stream.readSome(cast(size_t)classIdentifierLength.value);

				RawConvTypes!ulong parentInstanceIdentifierLength;
				stream.read(parentInstanceIdentifierLength.bytes);
				stage3_actor_create.parentInstanceIdentifier = cast(string)stream.readSome(cast(size_t)parentInstanceIdentifierLength.value);
			} else if (substage == 1) {
				RawConvTypes!ulong uidLength;
				stream.read(uidLength.bytes);
				stage3_actor_verify.uid = cast(string)stream.readSome(cast(size_t)uidLength.value);
				
				RawConvTypes!ulong classInstanceIdentifierLength;
				stream.read(classInstanceIdentifierLength.bytes);
				stage3_actor_verify.classInstanceIdentifier = cast(string)stream.readSome(cast(size_t)classInstanceIdentifierLength.value);

				ubyte[1] success;
				stream.read(success);
				stage3_actor_verify.success = cast(bool)success[0];
			} else if (substage == 2) {
				RawConvTypes!ulong classInstanceIdentifierLength;
				stream.read(classInstanceIdentifierLength.bytes);
				stage3_actor_destroy = cast(string)stream.readSome(cast(size_t)classInstanceIdentifierLength.value);

			} else if (substage == 3) {
				RawConvTypes!ulong classInstanceIdentifierLength;
				stream.read(classInstanceIdentifierLength.bytes);
				stage3_actor_destroy_verify.classInstanceIdentifier = cast(string)stream.readSome(cast(size_t)classInstanceIdentifierLength.value);
				
				ubyte[1] success;
				stream.read(success);
				stage3_actor_destroy_verify.success = cast(bool)success[0];
			} else if (substage == 4) {
				RawConvTypes!ulong uidLength;
				stream.read(uidLength.bytes);
				stage3_method_call.uid = cast(string)stream.readSome(cast(size_t)uidLength.value);
				
				RawConvTypes!ulong classInstanceIdentifierLength;
				stream.read(classInstanceIdentifierLength.bytes);
				stage3_method_call.classInstanceIdentifier = cast(string)stream.readSome(cast(size_t)classInstanceIdentifierLength.value);
				
				RawConvTypes!ulong methodNameLength;
				stream.read(methodNameLength.bytes);
				stage3_method_call.methodName = cast(string)stream.readSome(cast(size_t)methodNameLength.value);
				
				RawConvTypes!ulong dataLength;
				stream.read(dataLength.bytes);
				stage3_method_call.data = stream.readSome(cast(size_t)dataLength.value);
				
				ubyte[1] expectsReturnValue;
				stream.read(expectsReturnValue);
				stage3_method_call.expectsReturnValue = cast(bool)expectsReturnValue[0];
			} else if (substage == 5) {
				RawConvTypes!ulong uidLength;
				stream.read(uidLength.bytes);
				stage3_method_return.uid = cast(string)stream.readSome(cast(size_t)uidLength.value);
				
				RawConvTypes!ulong dataLength;
				stream.read(dataLength.bytes);
				stage3_method_return.data = stream.readSome(cast(size_t)dataLength.value);
			} else if (substage == 6) {
				RawConvTypes!ulong classInstanceIdentifierLength;
				stream.read(classInstanceIdentifierLength.bytes);
				stage3_actor_error.classInstanceIdentifier = cast(string)stream.readSome(cast(size_t)classInstanceIdentifierLength.value);

				RawConvTypes!ulong messageLength;
				stream.read(messageLength.bytes);
				stage3_actor_error.message = cast(string)stream.readSome(cast(size_t)messageLength.value);
			}
		}
	}

	void send(TCPConnection stream) {
		ubyte[] v;

		v = [stage, substage];
		stream.write(v);

		if (stage == 0) {
			if (substage == 0) {
				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage0_init.length));
				stream.write(stage0_init);
			} else if (substage == 1 || substage == 2) {
				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage0_capabilities.length));
				foreach(str; stage0_capabilities) {
					stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(str.length));
					stream.write(str);
				}
			}
		} else if (stage == 1) {
			if (substage == 0) {
				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(ulong.sizeof));
				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage1_client_sync));
			} else if (substage == 1) {
				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(2));
				stream.write(cast(ubyte[])[stage1_server_sync.isOverloaded, stage1_server_sync.willUse]);
			}
		} else if (stage == 2) {
			if (substage == 0) {
				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(0));
			} else if (substage == 1) {
 	      		ubyte[] dataOut;
				foreach(actor; stage2_actors) {
					dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(actor.length) ~ cast(ubyte[])actor;
				}

				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(dataOut.length));
				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage2_actors.length));
				stream.write(dataOut);
			} else if (substage == 2) {
				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage2_actor_request.length));
				stream.write(stage2_actor_request);
			} else if (substage == 3) {
				ubyte[] dataOut;

				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage2_actor.name.length);
				dataOut ~= cast(ubyte[])stage2_actor.name;

				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage2_actor.methods.length);

				foreach(method; stage2_actor.methods) {
					dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(method.name.length);
					dataOut ~= cast(ubyte[])method.name;

					dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(method.return_type.length);
					dataOut ~= cast(ubyte[])method.return_type;

					dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(method.arguments.length);

					foreach(arg; method.arguments) {
						dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(arg.type.length);
						dataOut ~= cast(ubyte[])arg.type;
						dataOut ~= cast(ubyte)arg.usage;
					}
				}

				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(dataOut.length));
				stream.write(dataOut);
			}
		} else if (stage == 3) {
			if (substage == 0) {
				ubyte[] dataOut;

				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_actor_create.uid.length);
				dataOut ~= cast(ubyte[])stage3_actor_create.uid;
				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_actor_create.classIdentifier.length);
				dataOut ~= cast(ubyte[])stage3_actor_create.classIdentifier;
				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_actor_create.parentInstanceIdentifier.length);
				dataOut ~= cast(ubyte[])stage3_actor_create.parentInstanceIdentifier;

				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(dataOut.length));
				stream.write(dataOut);
			} else if (substage == 1) {
				ubyte[] dataOut;
				
				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_actor_verify.uid.length);
				dataOut ~= cast(ubyte[])stage3_actor_verify.uid;
				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_actor_verify.classInstanceIdentifier.length);
				dataOut ~= cast(ubyte[])stage3_actor_verify.classInstanceIdentifier;
				dataOut ~= cast(ubyte)stage3_actor_verify.success;
				
				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(dataOut.length));
				stream.write(dataOut);
			} else if (substage == 2) {
				ubyte[] dataOut;

				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_actor_destroy.length);
				dataOut ~= cast(ubyte[])stage3_actor_destroy;

				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(dataOut.length));
				stream.write(dataOut);
			} else if (substage == 3) {
				ubyte[] dataOut;

				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_actor_destroy_verify.classInstanceIdentifier.length);
				dataOut ~= cast(ubyte[])stage3_actor_destroy_verify.classInstanceIdentifier;
				dataOut ~= cast(ubyte)stage3_actor_destroy_verify.success;

				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(dataOut.length));
				stream.write(dataOut);
			} else if (substage == 4) {
				ubyte[] dataOut;
				
				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_method_call.uid.length);
				dataOut ~= cast(ubyte[])stage3_method_call.uid;
				
				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_method_call.classInstanceIdentifier.length);
				dataOut ~= cast(ubyte[])stage3_method_call.classInstanceIdentifier;
				
				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_method_call.methodName.length);
				dataOut ~= cast(ubyte[])stage3_method_call.methodName;
				
				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_method_call.data.length);
				dataOut ~= stage3_method_call.data;
				dataOut ~= cast(ubyte)stage3_method_call.expectsReturnValue;
				
				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(dataOut.length));
				stream.write(dataOut);
			} else if (substage == 5) {
				ubyte[] dataOut;
				
				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_method_return.uid.length);
				dataOut ~= cast(ubyte[])stage3_method_return.uid;
				
				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_method_return.data.length);
				dataOut ~= stage3_method_return.data;
								
				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(dataOut.length));
				stream.write(dataOut);
			} else if (substage == 6) {
				ubyte[] dataOut;

				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_actor_error.classInstanceIdentifier.length);
				dataOut ~= cast(ubyte[])stage3_actor_error.classInstanceIdentifier;
				dataOut ~= cast(ubyte[ulong.sizeof])RawConvTypes!ulong(stage3_actor_error.message.length);
				dataOut ~= cast(ubyte[])stage3_actor_error.message;

				stream.write(cast(ubyte[ulong.sizeof])RawConvTypes!ulong(dataOut.length));
				stream.write(dataOut);
			}
		}

		stream.flush();
		logInfo("Sent something to %s", stream.remoteAddress.toString());
	}
}

ubyte[] readSome(TCPConnection stream, size_t amount) {
	ubyte[] ret;

	for(size_t i; i < amount; i++) {
		ubyte[1] v;
		stream.read(v);
		ret ~= v[0];
	}

	return ret;
}

union RawConvTypes(T) {
	T value;
	ubyte[T.sizeof] bytes;

	ubyte[T.sizeof] opCast() {
		return bytes;
	}
}

unittest {
	auto r = RawConvTypes!ulong(4);
	ubyte[] data = r.bytes;

	assert(data.length == 8);
	assert(data[0] == 4);
	for(size_t i=1; i < 8; i++) {
		assert(data[i] == 0);
	}
}

unittest {
	RawConvTypes!ulong data;
	data.bytes = [4, 0, 0, 0, 0, 0, 0, 0];
	assert(data.value == 4);
}

ulong utc0Time() {
	import std.datetime : SysTime, Clock;
	
	SysTime curr = Clock.currTime();
	curr -= curr.utcOffset;
	return curr.toUnixTime();
}

/**
 * Messages
 */

struct ServerLagReply {
	bool isOverloaded;
	bool willUse;
}

struct ActorInformation {
	string name;
	ActorMethod[] methods;
}

struct ActorMethod {
	string name;
	string return_type;
	ActorMethodArgument[] arguments;
}

struct ActorMethodArgument {
	string type;
	ActorMethodArgumentUsage usage;
}

enum ActorMethodArgumentUsage : ubyte {
	In,
	Out,
	Ref
}

struct ActorClassCreation {
	string uid;
	string classIdentifier;
	string parentInstanceIdentifier;
}

struct ActorClassCreationVerify {
	string uid;
	string classInstanceIdentifier;
	bool success;
}

struct ActorClassDestroyVerify {
	string classInstanceIdentifier;
	bool success;
}

struct ActorMethodCall {
	string uid;
	string classInstanceIdentifier;
	string methodName;
	ubyte[] data;
	bool expectsReturnValue;
}

struct ActorMethodReturn {
	string uid;
	ubyte[] data;
}

struct ActorError {
	string classInstanceIdentifier;
	string errorClassInstanceIdentifier;
	string message;
}

/**
 * Creation and sending of messages
 */

void askForActors(TCPConnection conn) {
	DakkaMessage sending;
	
	sending.stage = 2;
	sending.substage = 0;
	
	sending.send(conn);
}

void replyForActors(TCPConnection conn) {
	import dakka.base.registration.actors : possibleActorNames;
	DakkaMessage sending;
	
	sending.stage = 2;
	sending.substage = 1;
	sending.stage2_actors = possibleActorNames();

	sending.send(conn);
}

void askForActorInfo(TCPConnection conn, string name) {
	DakkaMessage sending;
	
	sending.stage = 2;
	sending.substage = 2;
	sending.stage2_actor_request = name;
	
	sending.send(conn);
}

void replyForActor(TCPConnection conn, string name) {
	import dakka.base.registration.actors : getActorInformation;
	DakkaMessage sending;
	
	sending.stage = 2;
	sending.substage = 3;
	sending.stage2_actor = getActorInformation(name);
	
	sending.send(conn);
}

void askForClassCreation(TCPConnection conn, string uid, string identifier, string parent) {
	DakkaMessage sending;

	sending.stage = 3;
	sending.substage = 0;
	sending.stage3_actor_create.uid = uid;
	sending.stage3_actor_create.classIdentifier = identifier;
	sending.stage3_actor_create.parentInstanceIdentifier = parent;

	sending.send(conn);
}

void handleRequestOfClassCreation(TCPConnection conn, RemoteDirector director, ActorClassCreation data) {
	string identifier;
	bool successful;

	// director, hi yeah we need the class created
	//   soo did you create it?
	//      oh you did, did you. So whats its id?
	//      oh you didn't, sorry to hear that.
	identifier = director.receivedCreateClass(conn.remoteAddress.toString(), data.uid, data.classIdentifier, data.parentInstanceIdentifier);
	successful = identifier !is null;

	DakkaMessage sending;
	
	sending.stage = 3;
	sending.substage = 1;
	sending.stage3_actor_verify.uid = data.uid;
	sending.stage3_actor_verify.classInstanceIdentifier = identifier;
	sending.stage3_actor_verify.success = successful;
	
	sending.send(conn);
}

void askForClassDeletion(TCPConnection conn, string identifier) {
	DakkaMessage sending;
	
	sending.stage = 3;
	sending.substage = 2;
	sending.stage3_actor_destroy = identifier;
	
	sending.send(conn);
}

void askToKill(TCPConnection conn, string identifier, bool success) {
	DakkaMessage sending;

	sending.stage = 3;
	sending.substage = 3;
	sending.stage3_actor_destroy_verify.classInstanceIdentifier = identifier;
	sending.stage3_actor_destroy_verify.success = success;

	sending.send(conn);
}

void classCallMethod(TCPConnection conn, string uid, string classInstanceIdentifier, string methodName, ubyte[] data, bool expects) {
	DakkaMessage sending;
	
	sending.stage = 3;
	sending.substage = 4;
	
	sending.stage3_method_call.uid = uid;
	sending.stage3_method_call.classInstanceIdentifier = classInstanceIdentifier;
	sending.stage3_method_call.methodName = methodName;
	sending.stage3_method_call.data = data;
	sending.stage3_method_call.expectsReturnValue = expects;
	
	sending.send(conn);
}

void classCallMethodReturn(TCPConnection conn, string uid, ubyte[] data) {
	DakkaMessage sending;
	
	sending.stage = 3;
	sending.substage = 5;
	
	sending.stage3_method_return.uid = uid;
	sending.stage3_method_return.data = data;
	
	sending.send(conn);
}

void classErroredReport(TCPConnection conn, string identifier, string identifier2, string message) {
	DakkaMessage sending;
	
	sending.stage = 3;
	sending.substage = 6;
	sending.stage3_actor_error.classInstanceIdentifier = identifier;
	sending.stage3_actor_error.errorClassInstanceIdentifier = identifier2;
	sending.stage3_actor_error.message = message;
	
	sending.send(conn);
}


/**
 * Communication to director
 */

enum DirectorCommunicationActions {
	AreYouStillThere, // not actually used. But its better then it dieing. Should a default instance be sent errornously.
	GoDie,
	CreateClass,
	DeleteClass,
	ClassCall,
	ClassError
}

void listenForCommunications(TCPConnection conn, RemoteDirector director) {
	Task task = runTask({
		// director assignment of task should be here. But we can't be sure it will be.

		while(conn.connected) {
			receive(
			(DirectorCommunicationActions action) {
				switch(action) {
					case DirectorCommunicationActions.GoDie:
						conn.close();
						break;
					default:
						break;
				}
			},
			(DirectorCommunicationActions action, string str1, string str2, string str3) {
				switch(action) {
					case DirectorCommunicationActions.CreateClass:
						askForClassCreation(conn, str1, str2, str3);
						break;
					case DirectorCommunicationActions.ClassError:
						classErroredReport(conn, str1, str2, str3);
						break;
					default:
						break;
				}
			},
			(DirectorCommunicationActions action, string identifier) {
				switch(action) {
					case DirectorCommunicationActions.DeleteClass:
						askForClassDeletion(conn, identifier);
						break;
					default:
						break;
				}
			},
			(DirectorCommunicationActions action, string uid, string cid, string mid, shared(ubyte[]) data, bool expects) {
				switch(action) {
					case DirectorCommunicationActions.ClassCall:
						classCallMethod(conn, uid, cid, mid, cast(ubyte[])data, expects);
						break;
					default:
						break;
				}
			});

			sleep(25.msecs);
		}
		
		director.unassign(conn.remoteAddress.toString());
	});

    director.assign(conn.remoteAddress.toString(), task);
	logInfo("Listening for connections from the director started up");
}

void logActorsInfo(ActorInformation info, string addr) {
	string desc;
	desc ~= "class " ~ info.name ~ " {\n";
	foreach(method; info.methods) {
		desc ~= "    " ~ method.return_type ~ " " ~ method.name ~ "(";
		foreach(arg; method.arguments) {
			if (arg.usage == ActorMethodArgumentUsage.In)
				desc ~= "in ";
			else if (arg.usage == ActorMethodArgumentUsage.Out)
				desc ~= "out ";
			else if (arg.usage == ActorMethodArgumentUsage.Ref)
				desc ~= "ref ";
			desc ~= arg.type ~ ", ";
		}
		if (method.arguments.length > 0)
			desc.length -= 2;
		desc ~= ");\n";
	}
	desc ~= "}";

	logInfo("Node %s has told us their actors %s information\n%s", addr, info.name, desc);
}