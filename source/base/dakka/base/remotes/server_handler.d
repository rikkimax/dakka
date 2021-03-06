﻿/*
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
module dakka.base.remotes.server_handler;
import dakka.base.remotes.defs;
import dakka.base.remotes.messages;
import vibe.d;
import std.string : join;

private shared {
	TCPListener[][] allConnections;
}

void handleServerMessageServer(DakkaServerSettings settings) {
	TCPListener[] listensOn = listenTCP(settings.port, (conn) {
		string addr = conn.remoteAddress.toString();
		logInfo("Client connected %s", addr);

		auto director = getDirector();
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
					if (!director.validateBuildInfo(received.stage0_init)) {
						conn.close();
						break;
					}
					logInfo("Client %s has build identifier of %s", addr, received.stage0_init);
				} else if (received.substage == 1) {
					// the client capabilities are the last message we should receive in stage 0
					stage = 1;

					if (!director.validateClientCapabilities(received.stage0_capabilities)) {
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
				} else if (received.substage == 1) {
					// TODO: how do we get the parent identifier, last arg?
					director.receivedEndClassCreate(received.stage3_actor_verify.uid, addr, received.stage3_actor_verify.classInstanceIdentifier, null);
					logInfo("Client %s has created an instance of class %s", addr, received.stage3_actor_verify.classInstanceIdentifier);
				} else if (received.substage == 2) {
					// request to delete an actor instance
					bool success = director.receivedDeleteClass(addr, received.stage3_actor_destroy);
					askToKill(conn, received.stage3_actor_destroy, success);
					logInfo("Client %s has requested us to kill %s and we are %s", addr, received.stage3_actor_destroy, success ? "complying" : "not complying");
				} else if (received.substage == 3) {
					// requested to delete an actor instance response
					logInfo("Client %s has replied that it has %s killed %s", addr, received.stage3_actor_destroy_verify.success ? "been" : "not been", received.stage3_actor_destroy_verify.classInstanceIdentifier);
				} else if (received.substage == 4) {
					if (received.stage3_method_call.expectsReturnValue)
						director.receivedBlockingMethodCall(received.stage3_method_call.uid, addr, received.stage3_method_call.classInstanceIdentifier, received.stage3_method_call.methodName, received.stage3_method_call.data);
					else {
						ubyte[] ret = director.receivedNonBlockingMethodCall(received.stage3_method_call.uid, addr, received.stage3_method_call.classInstanceIdentifier, received.stage3_method_call.methodName, received.stage3_method_call.data);
						classCallMethodReturn(conn, received.stage3_method_call.uid, ret);
					}
					logInfo("Client %s has asked us to call method %s on %s", addr, received.stage3_method_call.methodName, received.stage3_method_call.classInstanceIdentifier);
				} else if (received.substage == 5) {
					director.receivedClassReturn(received.stage3_method_return.uid, received.stage3_method_return.data);
				} else if (received.substage == 6) {
					director.receivedClassErrored(received.stage3_actor_error.classInstanceIdentifier, received.stage3_actor_error.errorClassInstanceIdentifier, received.stage3_actor_error.message);
				}
			}

			sleep(25.msecs);
		}

		logInfo("Client disconnected %s", addr);
	});

	synchronized {
		allConnections ~= cast(shared)listensOn;
	}
	logInfo("Started server listening");
}

void shutdownListeners() {
	synchronized {
		foreach(ac; allConnections) {
			foreach(c; ac) {
				(cast()c).stopListening();
			}
		}
	}
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