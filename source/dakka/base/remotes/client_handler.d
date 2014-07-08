module dakka.base.remotes.client_handler;
import dakka.base.remotes.defs;
import dakka.base.remotes.messages;
import vibe.d;
import std.string : join;

void handleClientMessageServer(DakkaRemoteServer settings) {
	runTask({
		foreach(ip; settings.ips) {
			auto conn = connectTCP(ip, settings.port);
			string addr = conn.remoteAddress.toString();
			logInfo("Connecting to server %s", addr);

			auto director = getDirector();
			listenForCommunications(conn, director);

			initMessage(conn);
			capabilitiesMessage(conn);

			ubyte stage;
			size_t iteration;

			logInfo("Main loop for server %s", addr);
			while(conn.connected) {
				if (iteration % 100 == 5 && stage > 0)
					sendSyncMessage(conn);

				// first lets setup up our loop iteration
				DakkaMessage sending;
				DakkaMessage received;
				received.receive(conn);

				if (received.stage == 0) {
					if (stage > 0) {
						// its an error to go here from stage 1/2/3
						conn.close();
						break;
					}

					if (received.substage == 2) {
						// hey its the server's capabilities!
						// which means we have finished stage 0
						stage = 1;
						sendSyncMessage(conn);

						director.receivedNodeCapabilities(addr, received.stage0_capabilities);
						logInfo("Server %s has capabilities %s", addr, received.stage0_capabilities.join(", "));
					}
				} else if (received.stage == 1) {
					if (stage == 0) {
						// its an error to go here from stage 0 to here
						conn.close();
						break;
					}

					if (received.substage == 1) {
						stage = 2;
						askForActors(conn);

						logInfo("Server says %s and %s", received.stage1_server_sync.isOverloaded ? "I'm overloaded" : "not overloaded", received.stage1_server_sync.willUse ? "will be used" : "won't be used");
					}
				} else if (received.stage == 2) {
					if (received.substage == 0) {
						replyForActors(conn);
						logInfo("Server %s asked for our actors", addr);
					} else if (received.substage == 1) {
						// should we do something here?
						foreach(actor; received.stage2_actors) {
							askForActorInfo(conn, actor);
						}

						logInfo("Server %s told us their actors %s", addr, received.stage2_actors.join(", "));
					} else if (received.substage == 2) {
						replyForActor(conn, received.stage2_actor_request);

						logInfo("Server %s asked for our actors %s information", addr, received.stage2_actor_request);
					} else if (received.substage == 3) {
						logActorsInfo(received.stage2_actor, addr);

						logInfo("Server %s has told us their actors %s information", addr, received.stage2_actor.name);
					}
				} else if (received.stage == 3) {
					if (received.substage == 0) {
						handleRequestOfClassCreation(conn, director, received.stage3_actor_create);
						logInfo("Server %s has asked us to create a %s with parent %s", addr, received.stage3_actor_create.classIdentifier, received.stage3_actor_create.parentInstanceIdentifier);
					} else if (received.substage == 1) {
						// TODO: how do we get the parent identifier, last arg?
						director.receivedEndClassCreate(received.stage3_actor_verify.uid, addr, received.stage3_actor_verify.classInstanceIdentifier, null);
						logInfo("Server %s has created an instance of class %s", addr, received.stage3_actor_verify.classInstanceIdentifier);
					} else if (received.substage == 2) {
						// request to delete an actor instance
						bool success = director.receivedDeleteClass(addr, received.stage3_actor_destroy);
						askToKill(conn, received.stage3_actor_destroy, success);
						logInfo("Server %s has requested us to kill %s and we are %s", addr, received.stage3_actor_destroy, success ? "complying" : "not complying");
					} else if (received.substage == 3) {
						// requested to delete an actor instance response
						logInfo("Server %s has replied that it has %s killed %s", addr, received.stage3_actor_destroy_verify.success ? "been" : "not been", received.stage3_actor_destroy_verify.classInstanceIdentifier);
					} else if (received.substage == 4) {
						if (received.stage3_method_call.expectsReturnValue)
							director.receivedBlockingMethodCall(received.stage3_method_call.uid, addr, received.stage3_method_call.classInstanceIdentifier, received.stage3_method_call.methodName, received.stage3_method_call.data);
						else {
							ubyte[] ret = director.receivedNonBlockingMethodCall(received.stage3_method_call.uid, addr, received.stage3_method_call.classInstanceIdentifier, received.stage3_method_call.methodName, received.stage3_method_call.data);
							classCallMethodReturn(conn, received.stage3_method_call.uid, ret);
						}
						logInfo("Server %s has asked us to call method %s on %s", addr, received.stage3_method_call.methodName, received.stage3_method_call.classInstanceIdentifier);
					} else if (received.substage == 5) {
						director.receivedClassReturn(received.stage3_method_return.uid, received.stage3_method_return.data);
					} else if (received.substage == 6) {
						director.receivedClassErrored(received.stage3_actor_error.classInstanceIdentifier, received.stage3_actor_error.errorClassInstanceIdentifier, received.stage3_actor_error.message);
					}
				}

				iteration++;
				sleep(25.msecs);
			}

			logInfo("Server disconnected %s", addr);
		}
	});
}

void initMessage(TCPConnection conn) {
	import dakka.base.defs : getBuildTitle;
	DakkaMessage sending;
	sending.stage = 0;
	sending.substage = 0;
	sending.stage0_init = getBuildTitle();
	sending.send(conn);
}

void capabilitiesMessage(TCPConnection conn) {
	import dakka.base.registration.capabilities : getCapabilities;
	DakkaMessage sending;

	sending.stage = 0;
	sending.substage = 1;
	sending.stage0_capabilities = getCapabilities();

	sending.send(conn);
}

void sendSyncMessage(TCPConnection conn) {
	// checks to make sure lag isn't too bad
	DakkaMessage sending;
	
	sending.stage = 1;
	sending.substage = 0;
	sending.stage1_client_sync = utc0Time();
	
	sending.send(conn);
}