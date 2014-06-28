import dakka.base.remotes.defs;
import dakka.base.registration.capabilities;
import dakka.base.registration.actors;
import dakka.base.defs;
import vibe.d;

void main(string[] args) {
	version(unittest){} else {
		//registerCapability("test");
		//registerCapability("testing budgies");

		//registerActor!MyActorA;

		if (args.length == 2) {
			setLogFile("client.txt", LogLevel.info);
			auto rconfig = DakkaRemoteServer("localhost", ["127.0.0.1"], 1171);
			clientConnect(rconfig);
		} else {
			setLogFile("server.txt", LogLevel.info);

			runTask({
				import std.process;
				sleep(2.seconds);
				execute([args[0], "something"]);
			});

			auto sconfig = DakkaServerSettings(1171);
			serverStart(sconfig);
		}

		//auto aref = new shared ActorRef!MyActorA;
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