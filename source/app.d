import dakka.base.remotes.defs;
import dakka.base.registration.capabilities;
import dakka.base.registration.actors;
import dakka.base.defs;
import vibe.d;

void main(string[] args) {
	version(unittest){} else {
		registerCapability("testing budgies");

		registerActor!MyActorA;

		if (args.length == 1 || (args.length == 2 && args[1] == "client")) {
			auto rconfig = DakkaRemoteServer("localhost", ["127.0.0.1"], 11728);
			clientConnect(rconfig);
			runTask({
				sleep(1.seconds);
				auto aref = new ActorRef!MyActorA;
				logInfo("id of actor created %s %s", aref.identifier, aref.isLocalInstance ? "is local" : "is not local");
				aref.test("Hiii from the client");
				aref.die();
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
		ofile.write("afile.txt", "got a message! " ~ s ~ "\n");
	}

	override void onStart() {
		import ofile = std.file;
		ofile.write("afile.txt", "I'm alive!\n");
	}

	override void onStop() {
		import ofile = std.file;
		ofile.append("afile.txt", "I'm dying!\n");
	}
}