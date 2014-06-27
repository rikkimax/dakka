module dakka.base.registration.capabilities;

/**
 * Capabilities of this node.
 */

private __gshared {
	string[] capabilities;
}

void registerCapability(string name) {
	synchronized {
		if (hasCapabilities() && hasCapability(name)) return;
		
		capabilities ~= name;
	}
}

bool hasCapability(string name) {
	synchronized {
		foreach(c; capabilities) {
			if (c == name) return true;
		}
		
		return false;
	}
}

bool hasCapabilities() {
	synchronized {
		return capabilities.length > 0;
	}
}

string[] getCapabilities() {
	return capabilities.dup;
}