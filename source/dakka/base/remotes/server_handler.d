module dakka.base.remotes.server_handler;
import dakka.base.remotes.defs;
import dakka.base.remotes.messages;
import vibe.d;
import std.string : join;

void handleServerMessageServer(DakkaServerSettings settings) {
	TCPListener[] listensOn = listenTCP(settings.port, (conn) {
		string addr = conn.remoteAddress.toString();
		logInfo("Client connected %s", addr);

		auto director = getDirector();
		auto validateClientCapabilities = director.validateClientCapabilities;
		auto validateBuildInfo = director.validateBuildInfo;
		listenForCommunications(conn, director);

		ubyte stage;

		logInfo("Main loop for client %s", addr);
		while(conn.connected) {
			DakkaMessage sending;
			DakkaMessage received;
			received.receive(conn);

			if (received.stage == 0) {
				if (stage > 0) {
					// its an error to go here from stage 1/2/3
					conn.close();
					break;
				}

				if (received.substage == 0) {
					if (validateBuildInfo !is null && !validateBuildInfo(received.stage0_init)) {
						conn.close();
						break;
					}
					logInfo("Client %s has build identifier of %s", addr, received.stage0_init);
				} else if (received.substage == 1) {
					// the client capabilities are the last message we should receive in stage 0
					stage = 1;

					if (validateClientCapabilities !is null && !validateClientCapabilities(received.stage0_capabilities)) {
						// ehh is this client okay to work with us?

						conn.close();
						break;
					}

					director.receivedNodeCapabilities(addr, received.stage0_capabilities);
					capabilitiesMessage(conn);

					logInfo("Client %s has capabilities %s", addr, received.stage0_capabilities.join(", "));
				}
			} else if (received.stage == 1) {
				if (stage == 0) {
					// its an error to go here from stage 0 to here
					conn.close();
					break;
				}

				if (received.substage == 0) {
					ulong now = utc0Time();
					stage = 2;
					askForActors(conn);
					ulong outBy = now - received.stage1_client_sync;

					if (outBy > settings.lagMaxTime) {
						// lag too high.
						// tell them that
						bool willUse = director.shouldContinueUsingNode(addr, outBy); // should get this some way though?
						lagMessage(conn, true, willUse);

						logInfo("Client %s is overloaded", addr);
					} else {
						lagMessage(conn, false, true);
						logInfo("Client %s is not overloaded", addr);
					}
				}
			} else if (received.stage == 2) {
				if (received.substage == 0) {
					replyForActors(conn);
					logInfo("Client %s asked for our actors", addr);
				} else if (received.substage == 1) {
					// should we do something here?
					foreach(actor; received.stage2_actors) {
						askForActorInfo(conn, actor);
					}
					
					logInfo("Client %s told us their actors %s", addr, received.stage2_actors.join(", "));
				} else if (received.substage == 2) {
					replyForActor(conn, received.stage2_actor_request);
					
					logInfo("Client %s asked for our actors %s information", addr, received.stage2_actor_request);
				} else if (received.substage == 3) {
					logInfo("Client %s has told us their actors %s information", addr, received.stage2_actor.name);
					logActorsInfo(received.stage2_actor, addr);
				}
			} else if (received.stage == 3) {
				if (received.substage == 0) {
					handleRequestOfClassCreation(conn, director, received.stage3_actor_create);
					logInfo("Client %s has asked us to create a %s with parent %s", addr, received.stage3_actor_create.classIdentifier, received.stage3_actor_create.parentInstanceIdentifier);
				}
			}

			sleep(25.msecs);
		}

		logInfo("Client disconnected %s", addr);
	});

	logInfo("Started server listening");
}

void capabilitiesMessage(TCPConnection conn) {
	import dakka.base.registration.capabilities : getCapabilities;
	DakkaMessage sending;
	
	sending.stage = 0;
	sending.substage = 2;
	sending.stage0_capabilities = getCapabilities();
	
	sending.send(conn);
}

void lagMessage(TCPConnection conn, bool tooHigh, bool willUse) {
	DakkaMessage sending;

	sending.stage = 1;
	sending.substage = 1;
	sending.stage1_server_sync.isOverloaded = tooHigh;
	sending.stage1_server_sync.willUse = willUse;
	
	sending.send(conn);
}