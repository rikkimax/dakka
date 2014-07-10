import dakka.base.remotes.defs;
import dakka.base.registration.capabilities;
import dakka.base.registration.actors;
import dakka.base.defs;
import vibe.d;

void main(string[] args) {
	version(unittest){} else {
		registerCapability("testing budgies");

		registerActor!MyActorA;
		registerActor!MyActorB;
		registerActor!TestStrategies;

		if (args.length == 1 || (args.length == 2 && args[1] == "client")) {
			registerCapability("test2");
			auto rconfig = DakkaRemoteServer("localhost", ["127.0.0.1"], 11728);
			clientConnect(rconfig);
			runTask({
				sleep(1.seconds);
				auto aref = new ActorRef!MyActorA;
				logInfo("id of actor created %s %s", aref.identifier, aref.isLocalInstance ? "is local" : "is not local");
				aref.onChildError(null, "okay hi there!");
				aref.test("Hiii from the client");
				//assert(aref.add(1, 2) == 3);
				aref.test2(new ActorRef!MyActorB);
				aref.die();

				auto tsref = new AllActorRefs!TestStrategies;
				assert(tsref.test(8) == ["8something", "8something"]);
			});
		}
		if (args.length == 1 || (args.length == 2 && args[1] == "server")) {
			registerCapability("test");
			auto sconfig = DakkaServerSettings(11728);
			serverStart(sconfig);
		}

		logInfo("Starting up main event loop.");
		runEventLoop();
	}
}

@DakkaCapability("test")
class MyActorA : Actor {
	this(Actor supervisor = null, bool isLocalInstance = true) { super(supervisor, isLocalInstance);}

	void test(string s){
		import ofile = std.file;
		ofile.append("afile.txt", "got a message! " ~ s ~ "\n");
	}

	int add(int x, int y) {
		return x + y;
	}

	void test2(MyActorB inst) {
		import ofile = std.file;
		ofile.append("afile.txt", "test ref " ~ inst.identifier ~ " " ~ inst.remoteAddressIdentifier ~ "\n");
		inst.hello();
	}

	override void onStart() {
		import ofile = std.file;
		ofile.write("afile.txt", "I'm alive!\n");
	}

	override void onStop() {
		import ofile = std.file;
		ofile.append("afile.txt", "I'm dying!\n");
	}

	override void onChildError(Actor actor, string message) {
		import ofile = std.file;
		ofile.append("afile.txt", "I child errored! " ~ (actor is null ? "and its null" : actor.identifier) ~ "\n");
	}
}

@DakkaCapability("test2")
class MyActorB : Actor {
	this(Actor supervisor = null, bool isLocalInstance = true) { super(supervisor, isLocalInstance);}

	void hello() {
		import ofile = std.file;
		ofile.write("afile2.txt", "Saying hello!\n");
	}
}

@DakkaSingleton
class TestStrategies : Actor {
	@DakkaCall(DakkaCallStrategy.Sequentially)
	string test(int x) {
		return to!string(x) ~ "something";
	}

	@DakkaCall(DakkaCallStrategy.Until, "1something")
	string test2(int x) {
		return to!string(x) ~ "something";
	}
}