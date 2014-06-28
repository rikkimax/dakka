import dakka.base.remotes.defs;
import dakka.base.registration.capabilities;
import dakka.base.registration.actors;
import dakka.base.defs;
import vibe.d;

void main(string[] args) {
	version(unittest){} else {
		registerCapability("test");
		registerCapability("testing budgies");

		registerActor!MyActorA;

		auto rconfig = DakkaRemoteServer("localhost", ["127.0.0.1"], 11728);
		clientConnect(rconfig);
		auto sconfig = DakkaServerSettings(11728);
		serverStart(sconfig);

		auto aref = new shared ActorRef!MyActorA;
		logInfo("Starting up main event loop.");
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