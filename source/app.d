import dakka.base.remotes.defs;
import dakka.base.registration.capabilities;
import dakka.base.registration.actors;
import dakka.base.defs;
import vibe.d;

shared static this() {
	version(unittest){} else {
		registerCapability("test");
		registerCapability("testing budgies");

		registerActor!MyActorA;

		auto aref = new shared ActorRef!MyActorA;

		auto sconfig = DakkaServerSettings(1172);
		serverStart(sconfig);
		auto rconfig = DakkaRemoteServer("localhost", ["127.0.0.1"], 1172);
		clientConnect(rconfig);
		runEventLoop();
	}
}

class MyActorA : Actor {
shared:
	this(shared(Actor) supervisor = null) {
		super(supervisor);
		if (__ctfe) return;
	}

	void test(string s){}
}