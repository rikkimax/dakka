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
```D
void main() {
	registerCapability("test");
	registerActor!MyActorA;

	MyActorA aref = new ActorRef!MyActorA;
	aref.test();
	aref.die();
}
```