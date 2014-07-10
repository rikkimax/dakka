Dakka
=====

Actor based framework in D using Vibe for RPC.

Features:
---------
* Local actor references
* Remote node connections, using given ip/port
* Remote actor calling
* On start/stop/error support
* Capabilities per node (can this node do x? if not which can do to create a reference?)
* Seemless integration of both actor references to actors
* Singleton (controller classes) actor support per node, works with
``
AllActorRefs
``
for calling them e.g. sequentially.

TODO:
-----
* Supporting of exceptions on error for remote'd calling
* Killing remote nodes
* Security between nodes
* Load balancing

Example:
--------

__Definition of an actor:__
```D
@DakkaCapability("test")
class MyActorA : Actor {
	this(Actor supervisor = null, bool isLocalInstance = true) { super(supervisor, isLocalInstance);}

	void test(string s){
		logInfo("got a message! %s", s);
	}

	override void onStart() {
		logInfo("Starting actor %s %s", typeText!MyActorA, identifier);
	}

	override void onStop() {
		logInfo("Stopping actor %s %s", typeText!MyActorA, identifier);
	}

	override void onChildError(Actor actor, string message) {
		logInfo("Actor %s %s has child %s that has errored with %s", typeText!MyActorA, identifier, actor.identifier, message);
	}
}
```

__Usage of an actor:__

The simplist form:
```D
void main() {
	registerCapability("test");
	registerActor!MyActorA;

	MyActorA aref = new ActorRef!MyActorA;
	aref.test();
	aref.die();
}
```

But with remote nodes:

_server_
```D
void main() {
	registerCapability("test");
	registerActor!MyActorA;

	auto sconfig = DakkaServerSettings(11728);
	serverStart(sconfig);

	runEventLoop();
}
```

_client_
```D
void main() {
	registerActor!MyActorA;

	auto rconfig = DakkaRemoteServer("localhost", ["127.0.0.1"], 11728);
	clientConnect(rconfig);

	runTask({
		sleep(1.seconds);
		MyActorA aref = new ActorRef!MyActorA;
		aref.test();
		aref.die();
	});

	runEventLoop();
}
```

Of course you are not forced to use actors on local/remote. This is merely an example. A server can use actors on the client.<br/>
As a note, from within an actor, use
``
actorOf!MyActorB
``
to get a reference to an actor.<br/>
This is a new actor instance of type MyActorB that is a child of the current one. Using the current one as the supervisor.